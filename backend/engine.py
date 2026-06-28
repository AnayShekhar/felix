"""Sequential workflow engine.

Runs an ordered list of tool steps, substituting {{N.field}} placeholders with
prior step results, broadcasting each step as it completes, and returning all
results. Tool execution is blocking, so each step runs in a thread to keep the
event loop responsive for WebSocket clients.
"""
import asyncio
import logging
import re
import time
from typing import Awaitable, Callable, List

import db
import llm
import memory
import tools
import websocket as ws_module

logger = logging.getLogger("lumis.engine")

_TOKEN = re.compile(r"\{\{\s*(\d+|last)\.(\w+)\s*\}\}")
_ANY_TOKEN = re.compile(r"\{\{[^}]*\}\}")

# Tools that run entirely in the cloud (no osascript / pmset / local files):
# they execute directly on Railway. Everything else is a macOS-local action and
# is dispatched to the Mac agent (backend/mac_agent.py) over the WebSocket.
#   - ios.*  return a phone-side URL scheme (no Mac involvement)
#   - web.search / web.fetch_page  use plain HTTP (requests/bs4)
CLOUD_TOOLS = {
    "ios.create_reminder",
    "ios.create_note",
    "ios.open_maps",
    "ios.send_message_draft",
    "web.search",
    "web.fetch_page",
}

# How long to wait for the Mac agent to return a result before giving up.
MAC_RESULT_TIMEOUT_S = 30.0


def _mac_offline_result(tool: str) -> dict:
    """Structured error contract when no Mac agent is available to run a tool."""
    return {
        "tool": tool,
        "status": "error",
        "message": "Mac agent not connected. Run mac_agent.py on your Mac.",
        "title": tool,
        "speak": "The Mac agent isn't connected. Start it on your Mac and try again.",
        "data": {"error": "mac_agent_offline"},
        "elapsed_ms": 0,
    }


def _mac_timeout_result(tool: str, elapsed_ms: float) -> dict:
    return {
        "tool": tool,
        "status": "error",
        "message": "Mac agent did not respond in time.",
        "title": tool,
        "speak": "The Mac agent didn't respond. Make sure it's running and try again.",
        "data": {"error": "mac_agent_timeout"},
        "elapsed_ms": elapsed_ms,
    }


async def _dispatch(
    tool: str,
    args: dict,
    action_id: int,
    session_id: str,
    broadcast: Callable[[dict], Awaitable[None]],
    loop: asyncio.AbstractEventLoop,
) -> dict:
    """Run a tool: cloud tools locally on Railway, macOS tools on the Mac agent."""
    if tool in CLOUD_TOOLS:
        return await loop.run_in_executor(None, tools.execute, tool, args)

    manager = ws_module.manager
    if not manager.mac_connected():
        return _mac_offline_result(tool)

    key = str(action_id)
    future = manager.create_pending(key)
    await broadcast({
        "session_id": session_id,
        "event": "execute_on_mac",
        "data": {"action_id": action_id, "tool": tool, "args": args},
    })

    start = time.monotonic()
    try:
        return await asyncio.wait_for(future, timeout=MAC_RESULT_TIMEOUT_S)
    except asyncio.TimeoutError:
        manager.cancel_pending(key)
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)
        logger.warning("Mac agent timed out running %s (action %s).", tool, action_id)
        return _mac_timeout_result(tool, elapsed_ms)


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
    user_id: str = db.GLOBAL_USER,
) -> List[dict]:
    """Execute steps in order, broadcasting progress; return all step results.

    `user_id` scopes both the action history and the learned memory to one
    account, so a user's phone and Mac share the same history + preferences.
    """
    # Scope learned memory to this account for the duration of the workflow.
    memory.set_user(user_id)

    results: List[dict] = []
    total = len(steps)
    loop = asyncio.get_event_loop()

    for i, step in enumerate(steps):
        tool = step.get("tool", "")
        args = _substitute(step.get("args", {}) or {}, results)

        # Log the attempt before executing so even a crash leaves a trail.
        action_id = db.record_action(session_id, tool, args, user_id=user_id)

        # Announce the step is starting so the UI can show live progress.
        await broadcast({
            "session_id": session_id,
            "event": "step_started",
            "data": {"index": i, "total": total, "tool": tool, "args": args,
                     "action_id": action_id},
        })

        result = await _dispatch(tool, args, action_id, session_id, broadcast, loop)
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

    # Record a one-sentence outcome as a "lumis" turn so follow-up commands in
    # this session ("do that again", "change the time") have context (Phase 3).
    try:
        done = [
            r.get("message") for r in results
            if r.get("status") == "success" and r.get("message")
        ]
        if done:
            llm.record_outcome(session_id, " ".join(done))
    except Exception:  # noqa: BLE001 - history is best-effort, never block the flow
        logger.warning("Failed to record session outcome.", exc_info=True)

    final = {
        "session_id": session_id,
        "event": "workflow_complete",
        "data": {"total": total, "steps": results},
    }
    set_latest(final)
    await broadcast(final)
    return results
