"""Mac-agent bridge: run a single tool on the user's Mac over the WebSocket.

The backend runs on Railway (Linux) and cannot run osascript/pmset/screencapture
or touch local files. Those tools execute on the Lumis Mac agent (mac_agent.py),
which connects to this backend as a special "mac" WebSocket client. This module
is the one place the agent loop talks to that Mac client.

It deliberately reuses the existing global ConnectionManager in websocket.py
(the same machinery the old engine used): one Mac agent, broadcast + a Future
keyed by action_id. We do NOT do per-user socket routing — the deployment is a
single paired Mac at a time, and pairing/ownership is enforced one layer up.

Flow:
  1. broadcast {"event": "execute_on_mac", "data": {action_id, tool, args}}
  2. await a Future registered under action_id
  3. the Mac agent replies {"event": "mac_result", "data": {action_id, result}},
     which websocket.ConnectionManager.resolve_pending fulfils the Future with.
"""
import asyncio
import logging
import time
from typing import Awaitable, Callable

import websocket as ws_module

logger = logging.getLogger("lumis.mac_bridge")

# How long to wait for the Mac agent to return a result before giving up.
MAC_RESULT_TIMEOUT_S = 30.0

Broadcast = Callable[[dict], Awaitable[None]]


def mac_connected() -> bool:
    """True if a Mac agent is currently connected and able to run tools."""
    return ws_module.manager.mac_connected()


def offline_result(tool: str) -> dict:
    """Structured error contract when no Mac agent is available to run a tool."""
    return {
        "tool": tool,
        "status": "error",
        "message": "Mac agent not connected. Make sure the Lumis Mac app is running.",
        "title": tool,
        "speak": "The Mac agent isn't connected. Start it on your Mac and try again.",
        "data": {"error": "mac_agent_offline"},
        "elapsed_ms": 0,
    }


def _timeout_result(tool: str, elapsed_ms: float) -> dict:
    return {
        "tool": tool,
        "status": "error",
        "message": "Mac agent did not respond in time. It may be busy or offline.",
        "title": tool,
        "speak": "The Mac agent didn't respond. Make sure it's running and try again.",
        "data": {"error": "mac_agent_timeout"},
        "elapsed_ms": elapsed_ms,
    }


async def run_on_mac(
    tool: str,
    args: dict,
    action_id: str,
    broadcast: Broadcast,
    timeout: float = MAC_RESULT_TIMEOUT_S,
) -> dict:
    """Dispatch one tool to the Mac agent and await its result.

    Always returns a result dict (never raises): an offline/timeout error
    contract if the Mac can't be reached, otherwise the agent's real result.
    `action_id` must be unique per in-flight call so results don't cross.
    """
    manager = ws_module.manager
    if not manager.mac_connected():
        return offline_result(tool)

    key = str(action_id)
    future = manager.create_pending(key)
    # Send to ONE Mac agent only (never broadcast — multiple registered agents
    # would each execute the tool, e.g. opening the same URL several times).
    delivered = await manager.send_to_mac({
        "event": "execute_on_mac",
        "data": {"action_id": action_id, "tool": tool, "args": args},
    })
    if not delivered:
        manager.cancel_pending(key)
        return offline_result(tool)

    start = time.monotonic()
    try:
        return await asyncio.wait_for(future, timeout=timeout)
    except asyncio.TimeoutError:
        manager.cancel_pending(key)
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)
        logger.warning("Mac agent timed out running %s (action %s).", tool, action_id)
        return _timeout_result(tool, elapsed_ms)
