import logging
import subprocess
import webbrowser
from fastapi import APIRouter
from pydantic import BaseModel

import websocket as ws_module
from gemini import parse_intent
from websocket import manager

logger = logging.getLogger("felix.automation")
router = APIRouter()


class IngestPayload(BaseModel):
    session_id: str
    image: str = ""
    voice_text: str = ""


def execute_mac_action(result: dict):
    """Executes local macOS automations based on parsed intent."""
    action = str(result.get("action", "")).lower()
    content = str(result.get("content", ""))
    target = str(result.get("target", "")).lower()
    title = str(result.get("title", ""))

    if not action or not content:
        return

    try:
        # 1. URL Opening (checks if URL format or browser target)
        if "url" in action or "browser" in target or content.startswith("http://") or content.startswith("https://") or ".com" in content or ".dev" in content:
            url = content.strip()
            if not url.startswith("http://") and not url.startswith("https://"):
                url = "https://" + url
            logger.info("Automation: Opening URL in browser: %s", url)
            webbrowser.open(url)

        # 2. App Launching (checks if open/launch action or app/mac target)
        elif "open" in action or "launch" in action or "mac" in target or "app" in target:
            app_name = content.strip()
            # If the content contains a long sentence, extract the clean name from the Title
            if len(app_name) > 30 or "launch" in app_name.lower():
                clean_title = title.replace("Open", "").replace("App", "").replace("launch", "").replace("Launch", "").strip()
                if clean_title:
                    app_name = clean_title
                else:
                    app_name = target.replace("App", "").replace("mac", "").strip()

            logger.info("Automation: Opening macOS app: %s", app_name)
            subprocess.run(["open", "-a", app_name], check=True)

    except Exception as exc:  # noqa: BLE001 - demo must not crash
        logger.error("Automation error executing %s: %s", action, exc)


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

    # Execute Mac action if applicable
    execute_mac_action(result)

    return result


@router.get("/latest")
async def latest():
    return ws_module.latest_result or {}


@router.get("/health")
async def health():
    return {"status": "ok"}
