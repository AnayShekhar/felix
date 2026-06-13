"""WebSocket connection manager and latest-result store."""
import logging
from typing import List, Optional

from fastapi import WebSocket

logger = logging.getLogger("felix.ws")

# In-memory store for the most recent broadcast payload.
latest_result: Optional[dict] = None


class ConnectionManager:
    def __init__(self) -> None:
        self.active: List[WebSocket] = []

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active.append(websocket)
        logger.info("WebSocket connected (%d active).", len(self.active))

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket in self.active:
            self.active.remove(websocket)
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


manager = ConnectionManager()
