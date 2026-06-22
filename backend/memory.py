"""Persistent user-preference memory for Felix (Phase 3).

Why this exists: Felix should get smarter the more you use it. After every
successful action we extract durable, deterministic preferences (where your
expense file lives, who you last emailed, that you use Spotify) and persist them
to a simple key/value JSON file. At planning time these are injected into the
LLM system prompt so commands can get shorter ("add this expense" already knows
the file) and defaults get filled in.

Stored as memory.json (key -> {"value", "updated"}) so it's human-inspectable
and editable. Standard library only.
"""
import json
import logging
import os
import time
from typing import Optional

logger = logging.getLogger("felix.memory")

MEMORY_PATH = os.path.expanduser(
    os.getenv("FELIX_MEMORY_PATH", os.path.join(os.path.dirname(__file__), "memory.json"))
)

# Human-readable labels so the injected prompt reads naturally.
_LABELS = {
    "expense_file": "Your expense spreadsheet file path",
    "music_service": "Preferred music service",
    "last_email_recipient": "Most recent email recipient",
}


def _load() -> dict:
    try:
        with open(MEMORY_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save(data: dict) -> None:
    tmp = MEMORY_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, MEMORY_PATH)  # atomic write


def get_all() -> dict:
    """Return memory as a flat {key: value} map for GET /memory."""
    return {k: v.get("value") for k, v in _load().items()}


def set_pref(key: str, value: str) -> None:
    """Store/overwrite one preference (skips empty values and no-op rewrites)."""
    value = str(value).strip()
    if not key or not value:
        return
    data = _load()
    if data.get(key, {}).get("value") == value:
        return
    data[key] = {"value": value, "updated": time.time()}
    _save(data)
    logger.info("Learned preference %s = %r", key, value)


def delete(key: str) -> bool:
    """Forget one preference. Returns True if it existed."""
    data = _load()
    if key in data:
        del data[key]
        _save(data)
        logger.info("Forgot preference %s", key)
        return True
    return False


def learn_from_action(tool: str, args: dict, result: dict) -> None:
    """Extract durable preferences from a SUCCESSFUL action and persist them.

    Deterministic only — we never guess. Called by the engine after each step.
    """
    if not result or result.get("status") != "success":
        return
    data = result.get("data") or {}

    if tool == "numbers.add_expense":
        if data.get("file"):
            set_pref("expense_file", data["file"])

    elif tool == "spotify.play_song":
        set_pref("music_service", "Spotify")

    elif tool == "gmail.draft_email":
        to = str(data.get("to") or args.get("to") or "").strip()
        if "@" in to:
            set_pref("last_email_recipient", to)


def as_prompt_block() -> Optional[str]:
    """Render current memory as a system-prompt addendum, or None if empty."""
    prefs = get_all()
    if not prefs:
        return None
    lines = [
        f"- {_LABELS.get(k, k)}: {v}"
        for k, v in prefs.items() if v
    ]
    if not lines:
        return None
    return (
        "\n\nUSER MEMORY (learned preferences — use these to fill in defaults "
        "when the user does not specify them; do not override anything the user "
        "explicitly states in this command):\n" + "\n".join(lines)
    )
