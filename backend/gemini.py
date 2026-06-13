"""Gemini intent parser with a deterministic mock fallback."""
import base64
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
    '{"action": string, "title": string, "content": string, "target": string}.\n\n'
    "Supported workflows and mappings:\n"
    "1. Notion Notes: Use this for study material, reading summaries, general notes, whiteboard transcription, etc.\n"
    "   - action: 'create_notes'\n"
    "   - target: 'notion'\n"
    "   - title: [Short, clean title for the notes]\n"
    "   - content: [Markdown-formatted detailed study notes or summary]\n"
    "2. Web Browsing: Use this when the user says 'open website', 'search for', 'go to', or asks to open a URL.\n"
    "   - action: 'open_url'\n"
    "   - target: 'browser'\n"
    "   - title: [Name of the site, e.g., YouTube, Google, GitHub]\n"
    "   - content: [The full valid URL beginning with http:// or https://]\n"
    "3. Mac Apps: Use this when the user wants to launch an app on their Mac (Spotify, Calculator, Safari, Slack, Notes, etc.).\n"
    "   - action: 'open_app'\n"
    "   - target: 'mac'\n"
    "   - title: [App Name, capitalized]\n"
    "   - content: [The exact macOS App bundle name to open, e.g., 'Spotify', 'Calculator', 'Safari', 'Slack', 'Notes', 'Terminal']\n"
    "4. Todo Tasks: Use this for tasks, reminders, or todo list additions.\n"
    "   - action: 'create_task'\n"
    "   - target: 'kanban'\n"
    "   - title: [Clean task title]\n"
    "   - content: [Description or subtasks of the todo]\n\n"
    "Example user voice: 'open google.com'\n"
    "Example output: {\"action\": \"open_url\", \"title\": \"Google\", \"content\": \"https://google.com\", \"target\": \"browser\"}"
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
        from google.genai import types

        client = genai.Client(api_key=GEMINI_API_KEY)
        contents = []

        # Parse base64 image if present
        if image:
            clean_image = image
            if "," in image:
                clean_image = image.split(",", 1)[1]
            
            try:
                image_bytes = base64.b64decode(clean_image)
                contents.append(
                    types.Part.from_bytes(
                        data=image_bytes,
                        mime_type="image/jpeg"
                    )
                )
            except Exception as e:
                logger.warning("Failed to decode base64 image (%s); skipping image context.", e)

        # Append the prompt text
        user_prompt = (
            f"User voice command: {voice_text}\n\n"
            "Analyze the image context (if provided) and user voice command to generate the structured JSON payload. "
            "Return ONLY the raw JSON object conforming to the schema and instructions. Do not wrap in markdown code blocks."
        )
        contents.append(user_prompt)

        # Call generate_content with system_instruction in config
        response = client.models.generate_content(
            model=MODEL,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION
            )
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
