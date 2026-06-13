"""Felix pipeline: INPUT -> LLM PLANNER -> WORKFLOW ENGINE -> REAL ACTIONS."""
import logging

from fastapi import APIRouter
from pydantic import BaseModel

import engine
import websocket as ws_module
from llm import parse_plan
from websocket import manager

logger = logging.getLogger("felix.routes")
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
    plan = parse_plan(payload.voice_text, payload.image)
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


@router.get("/health")
async def health():
    return {"status": "ok"}
