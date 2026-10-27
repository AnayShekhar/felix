"""Background autonomous-task queue for Felix (Phase 5).

Why this exists: some commands are multi-step jobs the user shouldn't have to
wait on synchronously ("research X, make a deck, email it to Sam"). This module
accepts a natural-language instruction, plans it into a tool workflow via the
LLM, and runs it on a background asyncio worker so POST /ingest stays snappy.
Progress is tracked per-task and broadcast over the WebSocket as each step
completes.

Runs the same ReAct agent as /ingest, but with a custom broadcast that also
maintains per-task progress state and forwards the underlying step events so the
existing UI keeps working. asyncio + stdlib only.
"""
import asyncio
import logging
import uuid
from typing import Optional

import db
import memory
from agent import FelixAgent
from websocket import manager

logger = logging.getLogger("felix.tasks")

# task_id -> task record (in-memory; tasks are ephemeral background jobs).
_tasks: dict[str, dict] = {}
_queue: "asyncio.Queue[str]" = asyncio.Queue()
_worker_started = False


def create_task(instruction: str, session_id: str, user_id: str = db.GLOBAL_USER) -> str:
    """Register a task and enqueue it for background execution."""
    task_id = "task-" + uuid.uuid4().hex[:8]
    _tasks[task_id] = {
        "task_id": task_id,
        "session_id": session_id,
        "user_id": user_id,
        "instruction": instruction,
        "status": "queued",
        "steps": [],
        "progress_pct": 0,
    }
    _queue.put_nowait(task_id)
    logger.info("Queued task %s: %r", task_id, instruction)
    return task_id


def get_status(task_id: str) -> Optional[dict]:
    """Return the public status contract for a task, or None if unknown."""
    t = _tasks.get(task_id)
    if t is None:
        return None
    return {
        "task_id": t["task_id"],
        "status": t["status"],
        "steps": t["steps"],
        "progress_pct": t["progress_pct"],
    }


async def _run_task(task_id: str) -> None:
    task = _tasks[task_id]
    task["status"] = "running"

    # Scope memory/history to this task's account.
    memory.set_user(task.get("user_id"))

    await manager.broadcast({
        "session_id": task["session_id"],
        "user_id": task.get("user_id"),
        "event": "task_started",
        "data": {"task_id": task_id, "instruction": task["instruction"],
                 "status": "running"},
    })

    async def task_broadcast(evt: dict) -> None:
        """Track per-task progress from the agent's events, then forward them.

        The ReAct agent decides steps as it goes (no fixed total), so progress is
        reported as a running step count and snaps to 100% on workflow_complete.
        """
        event = evt.get("event")
        data = evt.get("data", {})
        if event == "step_executed":
            task["steps"].append({
                "tool": data.get("tool"),
                "status": data.get("status", "success"),
                "result": {k: data.get(k) for k in ("tool", "status", "message", "title", "url")},
            })
            task["progress_pct"] = min(95, task["progress_pct"] + 10)
            await manager.broadcast({
                "session_id": task["session_id"],
                "user_id": task.get("user_id"),
                "event": "task_progress",
                "data": {"task_id": task_id, "progress_pct": task["progress_pct"],
                         "index": len(task["steps"]) - 1, "total": len(task["steps"]),
                         "step": task["steps"][-1]},
            })
        await manager.broadcast(evt)  # keep step_* / workflow_complete intact

    agent = FelixAgent(
        user_id=task.get("user_id", db.GLOBAL_USER),
        session_id=task["session_id"],
        broadcast=task_broadcast,
    )
    try:
        await agent.run(task["instruction"], None)
        task["status"] = "done"
        task["progress_pct"] = 100
    except Exception as exc:  # noqa: BLE001
        logger.error("Task %s execution failed: %s", task_id, exc)
        task["status"] = "failed"

    await _broadcast_complete(task)


async def _broadcast_complete(task: dict) -> None:
    await manager.broadcast({
        "session_id": task["session_id"],
        "user_id": task.get("user_id"),
        "event": "task_complete",
        "data": {"task_id": task["task_id"], "status": task["status"],
                 "progress_pct": task["progress_pct"], "steps": task["steps"]},
    })


async def _worker() -> None:
    logger.info("Task worker started.")
    while True:
        task_id = await _queue.get()
        try:
            await _run_task(task_id)
        except Exception:  # noqa: BLE001
            logger.exception("Unhandled error running task %s", task_id)
        finally:
            _queue.task_done()


def start_worker() -> None:
    """Start the background worker once, inside the running event loop."""
    global _worker_started
    if not _worker_started:
        asyncio.create_task(_worker())
        _worker_started = True
