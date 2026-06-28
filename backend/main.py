"""Lumis backend entrypoint."""
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

import auth
import db
import linking
import tasks
import websocket as ws_module
from routes import router
from websocket import manager

logging.basicConfig(level=logging.INFO)

# Ensure the SQLite stores exist before serving requests.
db.init_db()
auth.init_auth()
linking.init_linking()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start the background task worker inside the running event loop (Phase 5).
    tasks.start_worker()
    logging.getLogger("lumis.main").info(
        "Lumis backend listening on 0.0.0.0:%s", os.getenv("PORT", "8000")
    )
    yield


app = FastAPI(title="Lumis Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
app.include_router(auth.router)
app.include_router(linking.router)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    # Send the latest stored result immediately on connect.
    if ws_module.latest_result is not None:
        await websocket.send_json(ws_module.latest_result)
    try:
        while True:
            raw = await websocket.receive_text()
            # Inbound frames are control messages from the Mac agent
            # (register / mac_result); input clients only ever receive.
            await manager.handle_message(websocket, raw)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:  # noqa: BLE001
        manager.disconnect(websocket)


if __name__ == "__main__":
    # Local / container run: bind 0.0.0.0 and honor the platform-provided PORT
    # (Railway sets $PORT). The Procfile/railway.toml use the uvicorn CLI; this
    # block makes `python main.py` behave identically.
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    logging.getLogger("lumis.main").info("Starting uvicorn on 0.0.0.0:%s", port)
    uvicorn.run("main:app", host="0.0.0.0", port=port)
