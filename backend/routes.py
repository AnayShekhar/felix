"""Lumis pipeline: INPUT -> LLM PLANNER -> WORKFLOW ENGINE -> REAL ACTIONS."""
import asyncio
import logging
import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

import db
import engine
import memory
import tasks
import tools
import websocket as ws_module
from llm import parse_plan
from websocket import manager

logger = logging.getLogger("lumis.routes")
router = APIRouter()


class IngestPayload(BaseModel):
    session_id: str
    image: str = ""
    voice_text: str = ""


def _set_latest(event: dict) -> None:
    ws_module.latest_result = event


@router.post("/ingest")
async def ingest(payload: IngestPayload):
    # 1. LLM planner: intent -> ordered workflow of tool calls.
    logger.info("Ingest voice_text=%r (image=%s)", payload.voice_text, bool(payload.image))
    plan = parse_plan(payload.voice_text, payload.image, payload.session_id)
    steps = plan.get("steps") or [
        {"tool": "browser.open_url", "args": {"url": "https://google.com"}}
    ]

    # 2. Workflow engine: execute each real action in order, broadcasting progress.
    results = await engine.run_workflow(
        steps, payload.session_id, manager.broadcast, _set_latest
    )

    return {"steps": results}


@router.get("/latest")
async def latest():
    return ws_module.latest_result or {}


@router.get("/history")
async def history(limit: int = 50):
    """Return the last `limit` (default 50) actions Lumis has taken, newest first.

    Each entry: id, session_id, timestamp, tool_name, args, result, status,
    message, title, and undo_available.
    """
    return {"actions": db.get_history(limit)}


@router.post("/undo/{action_id}")
async def undo(action_id: int):
    """Undo a previously executed action by running its stored undo script.

    Returns 404 if the action does not exist and 400 if it cannot be undone.
    Broadcasts an `action_undone` event to all WebSocket clients on success.
    """
    action = db.get_action(action_id)
    if action is None:
        raise HTTPException(status_code=404, detail="Action not found.")
    if not action["undo_available"] or not action.get("undo_script"):
        raise HTTPException(status_code=400, detail="This action cannot be undone.")

    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(None, tools.run_undo, action["undo_script"])

    if result.get("status") == "success":
        db.mark_undone(action_id)
        await manager.broadcast({
            "session_id": action["session_id"],
            "event": "action_undone",
            "data": {"action_id": action_id, "tool": action["tool_name"], **result},
        })

    return {"action_id": action_id, **result}


class TaskPayload(BaseModel):
    instruction: str
    session_id: str = "task"


@router.post("/task")
async def create_task(payload: TaskPayload):
    """Queue a natural-language instruction for autonomous background execution.

    The instruction is planned into a tool workflow by the LLM and run on a
    background worker (does not block /ingest). Poll GET /task/{task_id}/status
    or listen for task_started / task_progress / task_complete WebSocket events.
    """
    task_id = tasks.create_task(payload.instruction, payload.session_id)
    return {"task_id": task_id, "status": "queued"}


@router.get("/task/{task_id}/status")
async def task_status(task_id: str):
    """Return a task's status: queued | running | done | failed, its steps, and
    progress_pct (0-100). 404 if the task id is unknown."""
    status = tasks.get_status(task_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return status


@router.get("/memory")
async def get_memory():
    """Return the preferences Lumis has learned about you as key/value pairs."""
    return {"memory": memory.get_all()}


@router.delete("/memory/{key}")
async def forget_memory(key: str):
    """Forget one learned preference by key. 404 if the key is unknown."""
    if not memory.delete(key):
        raise HTTPException(status_code=404, detail="No such memory key.")
    return {"status": "success", "message": f"Forgot '{key}'.", "key": key}


# Path to the self-contained web input client (../web-client/index.html).
_WEB_CLIENT = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "web-client", "index.html"
)


@router.get("/web", include_in_schema=False)
async def web_client():
    """Serve the self-contained web input client (camera + mic + wake word)."""
    if not os.path.exists(_WEB_CLIENT):
        raise HTTPException(status_code=404, detail="web-client/index.html not found.")
    return FileResponse(_WEB_CLIENT, media_type="text/html")


@router.get("/mac/status")
async def mac_status():
    """Whether a Mac agent (mac_agent.py) is currently connected.

    The Mac agent executes all osascript/pmset/local-file tools that Railway
    (Linux) cannot run. When `connected` is false, macOS-local tools fail with
    a "Mac agent not connected" error.
    """
    return {
        "connected": manager.mac_connected(),
        "agents": len(manager.mac_clients),
    }


@router.get("/health")
async def health():
    return {"status": "ok"}
