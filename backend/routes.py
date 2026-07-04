"""Lumis pipeline: INPUT -> ReAct AGENT -> REAL ACTIONS (cloud + Mac agent)."""
import asyncio
import logging
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

import db
import memory
import tasks
import tools
import websocket as ws_module
from agent import LumisAgent
from auth import current_user
from websocket import manager

logger = logging.getLogger("lumis.routes")
router = APIRouter()

# Live agent sessions keyed by session_id. In-memory and ephemeral (cleared on
# restart, which is fine). A session lingers here while it waits on the user to
# answer a clarifying question, so the next /ingest can resume it with context.
active_agents: dict[str, LumisAgent] = {}
_AGENT_TTL_S = 30 * 60


class IngestPayload(BaseModel):
    session_id: str
    image: str = ""
    voice_text: str = ""


def _set_latest(event: dict) -> None:
    ws_module.latest_result = event
    if event.get("user_id"):
        ws_module.latest_by_user[event["user_id"]] = event


def _prune_agents() -> None:
    now = time.time()
    stale = [sid for sid, a in active_agents.items()
             if now - a.last_active > _AGENT_TTL_S]
    for sid in stale:
        active_agents.pop(sid, None)


@router.post("/ingest")
async def ingest(payload: IngestPayload, user: dict = Depends(current_user)):
    """Start a new ReAct agent run, or resume one waiting on a clarifying question.

    Returns immediately; the agent runs in the background and streams progress
    over the WebSocket (the apps render results live, never from this response).
    """
    memory.set_user(user["id"])
    _prune_agents()
    logger.info("Ingest voice_text=%r (image=%s)", payload.voice_text, bool(payload.image))

    existing = active_agents.get(payload.session_id)
    if existing is not None and existing.pending_question and existing.user_id == user["id"]:
        # The user is answering Lumis's question — resume with full context.
        asyncio.create_task(existing.resume(payload.voice_text, payload.image or None))
        return {"status": "resumed", "session_id": payload.session_id}

    agent = LumisAgent(
        user_id=user["id"],
        session_id=payload.session_id,
        broadcast=manager.broadcast,
        set_latest=_set_latest,
    )
    active_agents[payload.session_id] = agent
    asyncio.create_task(agent.run(payload.voice_text, payload.image or None))
    return {"status": "accepted", "session_id": payload.session_id}


class AgentReplyPayload(BaseModel):
    session_id: str
    reply: str
    image: str = ""


@router.post("/agent/reply")
async def agent_reply(payload: AgentReplyPayload, user: dict = Depends(current_user)):
    """Answer an agent's clarifying question and continue its run.

    The iOS app can also simply re-capture on the same session_id (which routes
    back through /ingest -> resume); this endpoint is the explicit path.
    """
    agent = active_agents.get(payload.session_id)
    if agent is None or agent.user_id != user["id"]:
        raise HTTPException(status_code=404, detail="Session not found or expired.")
    asyncio.create_task(agent.resume(payload.reply, payload.image or None))
    return {"status": "accepted", "session_id": payload.session_id}


@router.get("/latest")
async def latest(user: dict = Depends(current_user)):
    """The signed-in account's most recent event (never another user's)."""
    return ws_module.latest_by_user.get(user["id"]) or {}


@router.get("/history")
async def history(limit: int = 50, user: dict = Depends(current_user)):
    """Return the last `limit` (default 50) actions for the signed-in account,
    newest first.

    Each entry: id, session_id, timestamp, tool_name, args, result, status,
    message, title, and undo_available.
    """
    return {"actions": db.get_history(limit, user_id=user["id"])}


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
            "user_id": action.get("user_id"),
            "event": "action_undone",
            "data": {"action_id": action_id, "tool": action["tool_name"], **result},
        })

    return {"action_id": action_id, **result}


class TaskPayload(BaseModel):
    instruction: str
    session_id: str = "task"


@router.post("/task")
async def create_task(payload: TaskPayload, user: dict = Depends(current_user)):
    """Queue a natural-language instruction for autonomous background execution.

    The instruction is planned into a tool workflow by the LLM and run on a
    background worker (does not block /ingest). Poll GET /task/{task_id}/status
    or listen for task_started / task_progress / task_complete WebSocket events.
    """
    task_id = tasks.create_task(payload.instruction, payload.session_id, user_id=user["id"])
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
async def get_memory(user: dict = Depends(current_user)):
    """Return the preferences Lumis has learned about the signed-in account."""
    memory.set_user(user["id"])
    return {"memory": memory.get_all()}


@router.delete("/memory/{key}")
async def forget_memory(key: str, user: dict = Depends(current_user)):
    """Forget one learned preference by key. 404 if the key is unknown."""
    memory.set_user(user["id"])
    if not memory.delete(key):
        raise HTTPException(status_code=404, detail="No such memory key.")
    return {"status": "success", "message": f"Forgot '{key}'.", "key": key}


# --------------------------------------------------------------------------- #
# Account connections (Chrome extension cookie sync)
# --------------------------------------------------------------------------- #
class CookieSyncRequest(BaseModel):
    service: str
    domain: str
    cookies: list[dict]


# Domains whose cookies indicate a service is actually signed in.
_SERVICE_DOMAINS = {
    "gmail": "google.com",
    "sheets": "google.com",
    "notion": "notion.so",
    "linkedin": "linkedin.com",
    "slack": "slack.com",
    "airtable": "airtable.com",
    "spotify": "spotify.com",
}


@router.get("/connect/status")
async def connection_status(user: dict = Depends(current_user)):
    """Which services this account has connected, and how fresh the extension's
    cookie sync is. Drives the status indicator on BOTH the iOS app and the
    extension popup:

      - ever_synced=False               → never connected
      - last_synced_at within a day     → connected + recently synced
      - last_synced_at older than that  → connected but stale (nudge a re-sync)
    """
    import connections

    details = connections.get_connection_details(user["id"])
    last = max((d["last_synced_at"] for d in details), default=None)
    return {
        "connected": [d["service"] for d in details],
        "services": details,
        "ever_synced": bool(details),
        "last_synced_at": last,
    }


@router.post("/connect/cookies/sync")
async def sync_cookies(request: CookieSyncRequest, user: dict = Depends(current_user)):
    """Receive cookies captured by the Chrome extension and inject them into the
    user's persistent Browserbase context so future cloud-browser sessions are
    already signed in."""
    import connections
    from cloud_browser import (
        CloudBrowserNotConfigured,
        get_or_create_user_context,
        inject_cookies_into_context,
    )

    if not request.cookies:
        raise HTTPException(status_code=400, detail="No cookies to sync.")

    # Don't mark a service connected off cookies that can't possibly sign it
    # in — the synced cookies must include the service's own domain.
    expected_domain = _SERVICE_DOMAINS.get(request.service)
    if expected_domain and not any(
        expected_domain in str(c.get("domain") or "") for c in request.cookies
    ):
        raise HTTPException(
            status_code=400,
            detail=(f"Those cookies don't look like {request.service} cookies "
                    f"(none are for {expected_domain}). Open {expected_domain}, "
                    "sign in, and try connecting again."),
        )

    try:
        context_id = await get_or_create_user_context(user["id"])
        # Browserbase allows one active session per context — close any live
        # tool session before opening the injection session.
        import cloud_browser as cb
        await cb.release_live_session(user["id"])
        await inject_cookies_into_context(context_id, request.cookies)
    except CloudBrowserNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("Cookie sync failed for user %s", user["id"])
        raise HTTPException(status_code=502, detail=f"Cookie sync failed: {exc}")

    connections.add_connected_service(user["id"], request.service)
    return {"success": True, "service": request.service}


@router.get("/connect/verify/{service}")
async def verify_service_cookies(service: str, user: dict = Depends(current_user)):
    """Check whether the user's Browserbase context actually has cookies for a
    service's domain. Returns cookie NAMES only — never values."""
    import browser_tools
    from cloud_browser import CloudBrowserNotConfigured

    domain = _SERVICE_DOMAINS.get(service, service)
    try:
        async with browser_tools.cloud_page(user["id"]) as page:
            cookies = await page.context.cookies()
    except CloudBrowserNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:  # noqa: BLE001
        logger.exception("Cookie verify failed for user %s", user["id"])
        raise HTTPException(status_code=502, detail=f"Verify failed: {exc}")

    matching = [c for c in cookies if domain in c.get("domain", "")]
    cookie_names = [c.get("name", "") for c in matching]
    return {
        "service": service,
        "domain": domain,
        "cookie_count": len(matching),
        "cookie_names": cookie_names,  # names only — never expose values
        "likely_synced": len(matching) > 0,
    }


@router.get("/health")
async def health():
    return {"status": "ok"}
