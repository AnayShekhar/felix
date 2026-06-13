"""HTTP routes for Felix."""
from fastapi import APIRouter
from pydantic import BaseModel

import websocket as ws_module
from gemini import parse_intent
from websocket import manager

router = APIRouter()


class IngestPayload(BaseModel):
    session_id: str
    image: str = ""
    voice_text: str = ""


@router.post("/ingest")
async def ingest(payload: IngestPayload):
    result = parse_intent(payload.voice_text, payload.image)

    event = {
        "session_id": payload.session_id,
        "event": "intent_processed",
        "data": result,
    }

    # Store latest and broadcast to all connected clients.
    ws_module.latest_result = event
    await manager.broadcast(event)

    return result


@router.get("/latest")
async def latest():
    return ws_module.latest_result or {}


@router.get("/health")
async def health():
    return {"status": "ok"}
