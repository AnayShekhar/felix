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
from brand_config import brand_env

import json
import logging
import os
import time
from contextvars import ContextVar
from typing import Optional

logger = logging.getLogger("felix.memory")

# Memory is scoped per account. The current request/workflow sets the active
# user; all reads/writes below transparently target that user's sub-store, so
# the phone and the Mac (signed into the same account) share one memory.
GLOBAL_USER = "_global"
_current_user: ContextVar[str] = ContextVar("felix_memory_user", default=GLOBAL_USER)


def set_user(user_id: Optional[str]) -> None:
    """Set the account whose memory subsequent calls read/write."""
    _current_user.set(user_id or GLOBAL_USER)

MEMORY_PATH = os.path.expanduser(
    brand_env("FELIX_MEMORY_PATH", os.path.join(os.path.dirname(__file__), "memory.json"))
)

# On hosted deploys (Railway) FELIX_MEMORY_PATH points at a mounted volume like
# /app/data/memory.json whose parent may not exist yet — create it up front.
_memory_dir = os.path.dirname(MEMORY_PATH)
if _memory_dir:
    os.makedirs(_memory_dir, exist_ok=True)

# Human-readable labels so the injected prompt reads naturally.
_LABELS = {
    "expense_file": "Your expense spreadsheet file path",
    "music_service": "Preferred music service",
    "last_email_recipient": "Most recent email recipient",
    "default_browser": "Default browser",
    "preferred_calendar": "Preferred calendar",
    "preferred_reminder_list": "Preferred reminder list",
    "frequent_contacts": "Frequent contacts",
    "home_folder": "Most-used folder",
    "command_patterns": "Most-used tool categories",
}

# Keys whose stored value is a JSON-encoded list (top-N rollups).
_LIST_KEYS = ("frequent_contacts", "command_patterns")

# Internal counter keys are prefixed with "_" and hidden from GET /memory and
# the prompt; they back the derived "most-used" preferences above.
_INTERNAL_PREFIX = "_"


def _load_all() -> dict:
    """Load the whole {user_id: {key: entry}} store, migrating legacy files.

    Older deploys stored a single flat {key: entry} map; if we detect that shape
    we nest it under GLOBAL_USER so existing memory isn't lost.
    """
    try:
        with open(MEMORY_PATH, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    # Legacy flat format: top-level values are entry dicts containing "value".
    if data and any(isinstance(v, dict) and "value" in v for v in data.values()):
        return {GLOBAL_USER: data}
    return data


def _load() -> dict:
    """The current account's memory sub-store ({key: entry})."""
    return _load_all().get(_current_user.get(), {})


def _save(data: dict) -> None:
    store = _load_all()
    store[_current_user.get()] = data
    tmp = MEMORY_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(store, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, MEMORY_PATH)  # atomic write


def get_all() -> dict:
    """Return memory as a flat {key: value} map for GET /memory.

    Internal counter keys (prefixed with "_") are hidden — they are an
    implementation detail backing the derived "most-used" preferences.
    """
    return {
        k: v.get("value")
        for k, v in _load().items()
        if not k.startswith(_INTERNAL_PREFIX)
    }


# ----------------------------------------------------------------------------
# Counter helpers (Phase 4)
#
# Several preferences ("preferred_calendar", "frequent_contacts", ...) are the
# most-frequent value over time, so we keep a small JSON-encoded {item: count}
# counter under an internal key and derive the top value(s) from it.
# ----------------------------------------------------------------------------

def _get_counter(key: str) -> dict:
    raw = _load().get(key, {}).get("value")
    if not raw:
        return {}
    try:
        c = json.loads(raw)
        return c if isinstance(c, dict) else {}
    except (json.JSONDecodeError, TypeError):
        return {}


def _bump_counter(key: str, item: str) -> dict:
    """Increment the count for `item` in the internal counter `key`."""
    item = str(item or "").strip()
    if not item:
        return _get_counter(key)
    data = _load()
    raw = data.get(key, {}).get("value")
    try:
        counts = json.loads(raw) if raw else {}
        if not isinstance(counts, dict):
            counts = {}
    except (json.JSONDecodeError, TypeError):
        counts = {}
    counts[item] = int(counts.get(item, 0)) + 1
    data[key] = {"value": json.dumps(counts), "updated": time.time()}
    _save(data)
    return counts


def _top_items(counter: dict, n: int = 1) -> list:
    """Return the `n` highest-count items (ties broken by recency-insensitive sort)."""
    return [k for k, _ in sorted(counter.items(), key=lambda kv: kv[1], reverse=True)][:n]


def _decode_list(value) -> list:
    """Decode a stored list value (JSON list, or comma-separated fallback)."""
    if not value:
        return []
    if isinstance(value, list):
        return value
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return [str(x) for x in parsed]
    except (json.JSONDecodeError, TypeError):
        pass
    return [s.strip() for s in str(value).split(",") if s.strip()]


# Friendly names for tool prefixes when summarizing command_patterns.
_CATEGORY_NAMES = {
    "media": "music",
    "gmail": "email",
    "numbers": "spreadsheets",
    "slides": "presentations",
    "web": "research",
}


def _tool_category(tool: str) -> str:
    prefix = str(tool or "").split(".", 1)[0]
    return _CATEGORY_NAMES.get(prefix, prefix)


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
    args = args or {}

    # --- Command-pattern rollup: track which tool categories are used most. ---
    cat = _tool_category(tool)
    if cat:
        counts = _bump_counter("_command_pattern_counts", cat)
        set_pref("command_patterns", json.dumps(_top_items(counts, 5)))

    if tool == "numbers.add_expense":
        if data.get("file"):
            set_pref("expense_file", data["file"])

    elif tool == "media.open_spotify":
        set_pref("music_service", "Spotify")

    elif tool == "media.open_apple_music":
        set_pref("music_service", "Apple Music")

    elif tool == "gmail.draft_email":
        to = str(data.get("to") or args.get("to") or "").strip()
        if "@" in to:
            set_pref("last_email_recipient", to)
            counts = _bump_counter("_contact_counts", to)
            set_pref("frequent_contacts", json.dumps(_top_items(counts, 5)))

    elif tool == "browser.open_url":
        # browser.open_url (and Gmail) always drive Chrome in this build.
        set_pref("default_browser", "Chrome")

    elif tool == "calendar.create_event":
        cal = str(data.get("calendar_name") or args.get("calendar_name") or "").strip()
        if cal:
            counts = _bump_counter("_calendar_counts", cal)
            top = _top_items(counts, 1)
            if top:
                set_pref("preferred_calendar", top[0])

    elif tool == "reminders.add_item":
        lst = str(data.get("list_name") or args.get("list_name") or "").strip()
        if lst:
            counts = _bump_counter("_reminder_list_counts", lst)
            top = _top_items(counts, 1)
            if top:
                set_pref("preferred_reminder_list", top[0])

    elif tool == "contacts.find":
        # Count each resolved contact (prefer email, fall back to name).
        for m in (data.get("results") or []):
            if not isinstance(m, dict):
                continue
            ident = str(m.get("email") or m.get("name") or "").strip()
            if ident:
                counts = _bump_counter("_contact_counts", ident)
                set_pref("frequent_contacts", json.dumps(_top_items(counts, 5)))

    elif tool.startswith("finder."):
        # Infer the most-used directory from any path the finder op touched.
        path = (
            data.get("path")
            or data.get("destination")
            or data.get("new_path")
            or args.get("path")
            or args.get("destination")
        )
        if path:
            directory = os.path.dirname(str(path)) or str(path)
            if directory:
                counts = _bump_counter("_folder_counts", directory)
                top = _top_items(counts, 1)
                if top:
                    set_pref("home_folder", top[0])


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


def get_context_block() -> str:
    """Render ALL current memory as a natural-language paragraph (Phase 4).

    Example: "The user's expense file is at ~/Documents/Expenses. Their
    preferred calendar is 'Personal'. They frequently email john@example.com.
    Their most used tools are calendar and notes." Returns "" if nothing is
    known yet. Injected into every LLM call via llm._system_instruction().
    """
    prefs = get_all()
    if not prefs:
        return ""

    parts = []
    if prefs.get("expense_file"):
        parts.append(f"The user's expense file is at {prefs['expense_file']}.")
    if prefs.get("music_service"):
        parts.append(f"They use {prefs['music_service']} for music.")
    if prefs.get("default_browser"):
        parts.append(f"Their default browser is {prefs['default_browser']}.")
    if prefs.get("preferred_calendar"):
        parts.append(f"Their preferred calendar is '{prefs['preferred_calendar']}'.")
    if prefs.get("preferred_reminder_list"):
        parts.append(
            f"Their preferred reminder list is '{prefs['preferred_reminder_list']}'."
        )
    if prefs.get("home_folder"):
        parts.append(f"Their most-used folder is {prefs['home_folder']}.")
    if prefs.get("last_email_recipient"):
        parts.append(f"They most recently emailed {prefs['last_email_recipient']}.")

    contacts = _decode_list(prefs.get("frequent_contacts"))
    if contacts:
        parts.append(f"They frequently contact {', '.join(contacts)}.")

    patterns = _decode_list(prefs.get("command_patterns"))
    if patterns:
        parts.append(f"Their most used tools are {', '.join(patterns)}.")

    # Surface any other custom keys we don't have bespoke phrasing for.
    known = {
        "expense_file", "music_service", "default_browser", "preferred_calendar",
        "preferred_reminder_list", "home_folder", "last_email_recipient",
        "frequent_contacts", "command_patterns",
    }
    for key, value in prefs.items():
        if key not in known and value:
            parts.append(f"{_LABELS.get(key, key)}: {value}.")

    return " ".join(parts)
