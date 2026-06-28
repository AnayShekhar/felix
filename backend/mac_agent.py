"""Lumis Mac agent — the local "hands" of the split architecture.

The Lumis backend runs on Railway (Linux), which cannot run osascript, pmset,
screencapture, or touch the local filesystem. This agent runs on your Mac,
connects to the Railway backend over the same /ws WebSocket as a special "mac"
client, and executes those macOS-local tools locally on your behalf:

    Railway  = brain (cloud, always on, plans via Groq)
    mac_agent = hands (local, runs osascript/shell tools here)
    iOS app  = eyes and ears (mobile input)

Protocol
--------
On connect it sends            {"event": "register", "role": "mac"}.
The backend pushes             {"event": "execute_on_mac",
                                "data": {"action_id", "tool", "args"}}.
The agent runs the tool via tools.execute() and replies
                               {"event": "mac_result",
                                "data": {"action_id", "result"}}.

Run it with ../run_mac_agent.sh, or directly: ./venv/bin/python mac_agent.py
The backend URL comes from $LUMIS_BACKEND_URL (defaults to the Railway URL);
http(s):// is rewritten to ws(s):// and "/ws" is appended automatically.
stdlib + the existing `websockets` dependency only.
"""
import asyncio
import json
import logging
import os
import signal
import socket
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import websockets

import tools

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("lumis.mac_agent")

# Default to the deployed Railway backend so the agent works out of the box;
# override with LUMIS_BACKEND_URL=http://localhost:8000 for local development.
DEFAULT_BACKEND_URL = "https://lumis-production-b878.up.railway.app"

# Seconds between reconnect attempts when the connection drops.
RECONNECT_DELAY_S = 3.0


def _ws_url() -> str:
    base = (os.getenv("LUMIS_BACKEND_URL") or DEFAULT_BACKEND_URL).strip()
    base = base.rstrip("/")
    if base.startswith("https://"):
        base = "wss://" + base[len("https://"):]
    elif base.startswith("http://"):
        base = "ws://" + base[len("http://"):]
    return base + "/ws"


# --------------------------------------------------------------------------- #
# iPhone <-> Mac linking
# --------------------------------------------------------------------------- #
HEARTBEAT_S = 15.0
_STATE_DIR = Path(os.path.expanduser("~/.lumis"))


def _http_base() -> str:
    return (os.getenv("LUMIS_BACKEND_URL") or DEFAULT_BACKEND_URL).strip().rstrip("/")


def _mac_id() -> str:
    """Stable per-machine id, persisted so re-launches keep the same identity."""
    _STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = _STATE_DIR / "mac_id"
    if path.exists():
        return path.read_text().strip()
    new_id = str(uuid.uuid4())
    path.write_text(new_id)
    return new_id


def _mac_name() -> str:
    name = socket.gethostname().replace(".local", "")
    return name or "Mac"


def _post(path: str, body: dict) -> dict:
    req = urllib.request.Request(
        _http_base() + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())


def _get(path: str) -> dict:
    with urllib.request.urlopen(_http_base() + path, timeout=10) as resp:
        return json.loads(resp.read().decode())


async def linking_loop() -> None:
    """Keep the Mac marked "online" for its paired phone.

    Pairing itself (showing the 6-digit code, confirming it) is owned by the
    signed-in Lumis Mac app, which calls the authenticated /link endpoints. This
    loop only sends heartbeats while a pairing exists, so the phone can tell the
    Mac is reachable. It identifies the Mac by the shared ~/.lumis/mac_id file.
    """
    mac_id = _mac_id()
    while True:
        try:
            linked = (await asyncio.to_thread(_get, f"/link/mac/{mac_id}")).get("linked", False)
            if linked:
                await asyncio.to_thread(_post, "/link/heartbeat",
                                        {"mac_id": mac_id, "mac_name": _mac_name()})
            await asyncio.sleep(HEARTBEAT_S if linked else 5)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            logger.debug("Heartbeat poll failed (%s); retrying.", exc)
            await asyncio.sleep(5)
        except asyncio.CancelledError:
            raise


async def _handle_execute(ws, data: dict) -> None:
    """Run one execute_on_mac request locally and reply with mac_result."""
    action_id = data.get("action_id")
    tool = data.get("tool", "")
    args = data.get("args") or {}
    logger.info("Executing %s (action %s) args=%s", tool, action_id, args)

    # tools.execute is blocking (osascript/subprocess) — run it off the event
    # loop so the WebSocket keeps draining while a tool runs.
    try:
        result = await asyncio.to_thread(tools.execute, tool, args)
    except Exception as exc:  # noqa: BLE001 - report failure truthfully
        logger.exception("Tool %s crashed", tool)
        result = {
            "tool": tool,
            "status": "error",
            "message": f"Mac agent failed to execute {tool}: {exc}",
            "title": tool,
            "data": {"error": str(exc)},
        }

    await ws.send(json.dumps({
        "event": "mac_result",
        "data": {"action_id": action_id, "result": result},
    }))
    logger.info("Returned result for action %s (%s).", action_id, result.get("status"))


async def _session(url: str) -> None:
    """Connect once, register, and service execute_on_mac events until closed."""
    async with websockets.connect(url, max_size=None, ping_interval=20) as ws:
        await ws.send(json.dumps({"event": "register", "role": "mac"}))
        logger.info("Connected and registered as Mac agent: %s", url)

        async for raw in ws:
            try:
                msg = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if not isinstance(msg, dict):
                continue
            # We only act on execute_on_mac; all other broadcasts are ignored.
            if msg.get("event") == "execute_on_mac":
                # Run concurrently so a slow tool doesn't block the next request.
                asyncio.create_task(_handle_execute(ws, msg.get("data") or {}))


async def run() -> None:
    url = _ws_url()
    logger.info("Lumis Mac agent starting. Backend: %s", url)
    # Run iPhone<->Mac linking concurrently with the WS service loop.
    link_task = asyncio.create_task(linking_loop())
    try:
        while True:
            try:
                await _session(url)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - keep the agent alive
                logger.warning("Connection lost (%s). Reconnecting in %.0fs…",
                               exc, RECONNECT_DELAY_S)
            else:
                logger.info("Connection closed. Reconnecting in %.0fs…", RECONNECT_DELAY_S)
            await asyncio.sleep(RECONNECT_DELAY_S)
    finally:
        link_task.cancel()


def main() -> None:
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    task = loop.create_task(run())

    # Clean shutdown on Ctrl-C / SIGTERM (e.g. when the Mac app quits us).
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, task.cancel)
        except NotImplementedError:  # pragma: no cover - not on all platforms
            pass

    try:
        loop.run_until_complete(task)
    except (KeyboardInterrupt, asyncio.CancelledError):
        logger.info("Lumis Mac agent stopped.")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
