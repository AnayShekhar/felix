"""WebSocket connection manager, latest-result store, and Mac-agent routing.

The backend runs on Railway (Linux) where osascript/pmset/etc. cannot run, so
macOS-local tools are dispatched to a separate "mac" client (backend/mac_agent.py)
over this same /ws stream:

  - The Mac agent connects and registers with {"event": "register",
    "role": "mac"}.  We track those sockets so the engine can tell whether a
    Mac is available.
  - The engine broadcasts an "execute_on_mac" event and awaits a result by
    registering a Future keyed by action_id.  When the agent replies with
    {"event": "mac_result", "data": {"action_id", "result"}} we resolve it.
"""
import asyncio
import logging
from typing import Dict, List, Optional

from fastapi import WebSocket

logger = logging.getLogger("felix.ws")

# In-memory store for the most recent broadcast payload.
latest_result: Optional[dict] = None


class ConnectionManager:
    def __init__(self) -> None:
        self.active: List[WebSocket] = []
        # Sockets that registered as the macOS execution agent.
        self.mac_clients: List[WebSocket] = []
        # action_id -> Future awaiting the Mac agent's "mac_result".
        self.pending: Dict[str, asyncio.Future] = {}

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active.append(websocket)
        logger.info("WebSocket connected (%d active).", len(self.active))

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket in self.active:
            self.active.remove(websocket)
        if websocket in self.mac_clients:
            self.mac_clients.remove(websocket)
            logger.info("Mac agent disconnected (%d remaining).", len(self.mac_clients))
        logger.info("WebSocket disconnected (%d active).", len(self.active))

    async def broadcast(self, message: dict) -> None:
        dead: List[WebSocket] = []
        for ws in self.active:
            try:
                await ws.send_json(message)
            except Exception:  # noqa: BLE001
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)

    # ----- Mac agent registry -------------------------------------------------

    def register_mac(self, websocket: WebSocket) -> None:
        """Mark a connected socket as the macOS execution agent."""
        if websocket not in self.mac_clients:
            self.mac_clients.append(websocket)
        logger.info("Mac agent registered (%d connected).", len(self.mac_clients))

    def mac_connected(self) -> bool:
        return len(self.mac_clients) > 0

    # ----- execute_on_mac request/response correlation ------------------------

    def create_pending(self, action_id: str) -> asyncio.Future:
        """Register (and return) a Future the engine awaits for a mac_result."""
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        self.pending[action_id] = future
        return future

    def resolve_pending(self, action_id: str, result: dict) -> None:
        """Fulfil the engine's Future for action_id with the Mac agent's result."""
        future = self.pending.pop(action_id, None)
        if future is not None and not future.done():
            future.set_result(result)

    def cancel_pending(self, action_id: str) -> None:
        self.pending.pop(action_id, None)

    async def handle_message(self, websocket: WebSocket, raw: str) -> None:
        """Route an inbound WebSocket text frame from any client.

        Recognised control messages (sent by the Mac agent):
          - {"event": "register", "role": "mac"}
          - {"event": "mac_result", "data": {"action_id", "result"}}
        Anything else is ignored (the input clients only ever receive).
        """
        import json

        try:
            msg = json.loads(raw)
        except (ValueError, TypeError):
            return
        if not isinstance(msg, dict):
            return

        event = msg.get("event")
        if event == "register" and msg.get("role") == "mac":
            self.register_mac(websocket)
        elif event == "mac_result":
            data = msg.get("data") or {}
            action_id = data.get("action_id")
            result = data.get("result") or {}
            if action_id is not None:
                self.resolve_pending(str(action_id), result)


manager = ConnectionManager()
