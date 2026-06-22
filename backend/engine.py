"""Sequential workflow engine.

Runs an ordered list of tool steps, substituting {{N.field}} placeholders with
prior step results, broadcasting each step as it completes, and returning all
results. Tool execution is blocking, so each step runs in a thread to keep the
event loop responsive for WebSocket clients.
"""
import asyncio
import logging
import re
from typing import Awaitable, Callable, List

import db
import memory
import tools

logger = logging.getLogger("felix.engine")

_TOKEN = re.compile(r"\{\{\s*(\d+|last)\.(\w+)\s*\}\}")
_ANY_TOKEN = re.compile(r"\{\{[^}]*\}\}")


def _substitute(value, results: List[dict]):
    """Recursively replace {{N.field}} / {{last.field}} tokens using results.

    Any leftover {{...}} (e.g. a placeholder the model invented when no real
    value existed) is stripped so template junk never lands in a real artifact.
    """
    if isinstance(value, str):
        def repl(m):
            idx_raw, field = m.group(1), m.group(2)
            if not results:
                return m.group(0)
            idx = len(results) - 1 if idx_raw == "last" else int(idx_raw)
            if 0 <= idx < len(results):
                return str(results[idx].get(field, ""))
            return m.group(0)
        substituted = _TOKEN.sub(repl, value)
        return _ANY_TOKEN.sub("", substituted).strip()
    if isinstance(value, dict):
        return {k: _substitute(v, results) for k, v in value.items()}
    if isinstance(value, list):
        return [_substitute(v, results) for v in value]
    return value


async def run_workflow(
    steps: List[dict],
    session_id: str,
    broadcast: Callable[[dict], Awaitable[None]],
    set_latest: Callable[[dict], None],
) -> List[dict]:
    """Execute steps in order, broadcasting progress; return all step results."""
    results: List[dict] = []
    total = len(steps)
    loop = asyncio.get_event_loop()

    for i, step in enumerate(steps):
        tool = step.get("tool", "")
        args = _substitute(step.get("args", {}) or {}, results)

        # Log the attempt before executing so even a crash leaves a trail.
        action_id = db.record_action(session_id, tool, args)

        # Announce the step is starting so the UI can show live progress.
        await broadcast({
            "session_id": session_id,
            "event": "step_started",
            "data": {"index": i, "total": total, "tool": tool, "args": args,
                     "action_id": action_id},
        })

        result = await loop.run_in_executor(None, tools.execute, tool, args)
        results.append(result)

        # Persist the result + undo info so it shows up in /history.
        undo_available, undo_script = tools.build_undo(tool, args, result)
        db.complete_action(action_id, result, undo_available, undo_script)

        # Learn durable preferences from successful actions (Phase 3 memory).
        memory.learn_from_action(tool, args, result)

        event = {
            "session_id": session_id,
            "event": "step_executed",
            "data": {"index": i, "total": total, "tool": tool, "args": args,
                     "action_id": action_id, "undo_available": undo_available,
                     **result},
        }
        set_latest(event)
        await broadcast(event)

    final = {
        "session_id": session_id,
        "event": "workflow_complete",
        "data": {"total": total, "steps": results},
    }
    set_latest(final)
    await broadcast(final)
    return results
