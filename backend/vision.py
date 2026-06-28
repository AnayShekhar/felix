"""Capture the Mac screen for the ReAct agent's vision.

The agent's `capture_screen` action lets the planning model (llama-4-scout,
multimodal) *look* at the Mac to verify reality before deciding the next step.
The screenshot is taken by the Mac agent's `screen.capture` tool and returned
to Railway as a base64 PNG, which the agent then feeds back into the model.
"""
import logging
import time
from typing import Awaitable, Callable, Optional

import mac_bridge

logger = logging.getLogger("lumis.vision")

Broadcast = Callable[[dict], Awaitable[None]]


async def capture_mac_screen(
    broadcast: Broadcast, action_id: Optional[str] = None
) -> Optional[str]:
    """Return a base64-encoded PNG of the current Mac screen, or None.

    None means the Mac agent is offline, timed out, or the capture failed —
    the agent treats that as an observation, not a crash.
    """
    if action_id is None:
        action_id = f"screen-{int(time.monotonic() * 1000)}"

    result = await mac_bridge.run_on_mac(
        "screen.capture", {}, action_id, broadcast, timeout=15.0
    )
    if not result or result.get("status") != "success":
        logger.info("Screen capture unavailable: %s", (result or {}).get("message"))
        return None

    # screen.capture returns image_b64 at the top level (and under data).
    return result.get("image_b64") or (result.get("data") or {}).get("image_b64")
