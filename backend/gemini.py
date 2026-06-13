"""Gemini intent parser with a deterministic mock fallback."""
import json
import logging
import os

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("felix.gemini")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
MODEL = "gemini-2.5-flash"

SYSTEM_INSTRUCTION = (
    "You are an intent parser. Convert image context + user instruction into "
    "structured workflow JSON. Output ONLY JSON with the schema "
    '{"action": string, "title": string, "content": string, "target": string}.'
)


def _mock_result(voice_text: str) -> dict:
    """Deterministic fallback so the demo pipeline always works."""
    logger.warning("Falling back to mock Gemini result.")
    summary = voice_text.strip() or "No instruction provided."
    return {
        "action": "create_notes",
        "title": "Study Notes",
        "content": f"Summary based on instruction: {summary}",
        "target": "dashboard",
    }


def _strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        # remove opening fence (``` or ```json) and trailing fence
        text = text.split("\n", 1)[-1] if "\n" in text else text
        if text.endswith("```"):
            text = text[: -3]
        text = text.strip()
    return text


def parse_intent(voice_text: str, image: str) -> dict:
    """Call Gemini to turn voice + image into structured intent JSON.

    Returns a dict with keys: action, title, content, target.
    Falls back to a mock result if the key is missing or the call fails.
    """
    if not GEMINI_API_KEY:
        return _mock_result(voice_text)

    try:
        from google import genai

        client = genai.Client(api_key=GEMINI_API_KEY)

        user_content = (
            f"{SYSTEM_INSTRUCTION}\n\n"
            f"User instruction: {voice_text}\n"
            f"Image reference: {image}\n\n"
            "Return ONLY the JSON object."
        )

        response = client.models.generate_content(
            model=MODEL,
            contents=user_content,
        )

        raw = _strip_fences(response.text or "")
        data = json.loads(raw)

        return {
            "action": str(data.get("action", "create_notes")),
            "title": str(data.get("title", "Untitled")),
            "content": str(data.get("content", "")),
            "target": str(data.get("target", "dashboard")),
        }
    except Exception as exc:  # noqa: BLE001 - demo must never crash
        logger.warning("Gemini call failed (%s); using mock result.", exc)
        return _mock_result(voice_text)
