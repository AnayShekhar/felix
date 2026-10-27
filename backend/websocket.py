"""WebSocket connection manager + latest-result store.

The backend runs entirely in the cloud (Google APIs + Browserbase). The /ws
stream is one-directional in practice: the backend broadcasts agent progress +
results to connected clients, and inbound frames are ignored.

Sockets authenticate with the account token (`/ws?token=…`) and events carry a
`user_id`, so each client only ever receives its own account's events — one
phone never hears another user's results. Events without a user_id (none in
practice) go to everyone; sockets without a token receive only those.
"""
import logging
from typing import Dict, Optional

from fastapi import WebSocket

logger = logging.getLogger("felix.ws")

# Most recent user-scoped broadcast, keyed by user_id (replayed on connect).
latest_result: Optional[dict] = None  # legacy global (kept for GET /latest)
latest_by_user: Dict[str, dict] = {}


class ConnectionManager:
    def __init__(self) -> None:
        self.active: Dict[WebSocket, Optional[str]] = {}

    async def connect(self, websocket: WebSocket, user_id: Optional[str] = None) -> None:
        await websocket.accept()
        self.active[websocket] = user_id
        logger.info("WebSocket connected (user=%s, %d active).",
                    user_id or "anonymous", len(self.active))

    def disconnect(self, websocket: WebSocket) -> None:
        self.active.pop(websocket, None)
        logger.info("WebSocket disconnected (%d active).", len(self.active))

    async def broadcast(self, message: dict) -> None:
        """Send to the event's account only (or everyone if un-scoped)."""
        target = message.get("user_id")
        dead = []
        for ws, uid in list(self.active.items()):
            if target is not None and uid != target:
                continue
            try:
                await ws.send_json(message)
            except Exception:  # noqa: BLE001
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)

    async def handle_message(self, websocket: WebSocket, raw: str) -> None:
        """Inbound frames from input clients are ignored — clients only receive."""
        return


manager = ConnectionManager()
