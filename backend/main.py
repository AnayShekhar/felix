"""Felix backend entrypoint."""
import logging

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

import websocket as ws_module
from routes import router
from websocket import manager

logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Felix Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    # Send the latest stored result immediately on connect.
    if ws_module.latest_result is not None:
        await websocket.send_json(ws_module.latest_result)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:  # noqa: BLE001
        manager.disconnect(websocket)
