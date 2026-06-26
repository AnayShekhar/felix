"""Groq workflow planner with a deterministic keyword fallback.

The LLM converts user intent (voice + image) into an ordered workflow:
{"steps": [{"tool": string, "args": {}}, ...]}. No prose, no abstract labels.
Steps run in order; an arg string may reference a prior step's output via
{{N.field}} (e.g. {{0.url}}) so results chain forward.
"""
import base64
import json
import logging
import os
import re
import threading
import time
from datetime import datetime

from dotenv import load_dotenv

import memory

load_dotenv()

logger = logging.getLogger("felix.llm")

# ----------------------------------------------------------------------------
# Conversation history within a session (Phase 3)
#
# Keep a short rolling transcript per session so follow-up commands like
# "do that again", "add another one", or "change the time to 3pm instead" have
# context. Stored in-memory only (ephemeral); cleared after 2h of inactivity.
# ----------------------------------------------------------------------------

# session_id -> {"turns": [{"role": "user"|"felix", "content": str}, ...],
#                "last_activity": float}
session_history: dict = {}
_history_lock = threading.Lock()

_HISTORY_MAX_TURNS = 10      # keep the last 10 turns per session
_HISTORY_INJECT_TURNS = 5    # inject the last 5 into the prompt
_HISTORY_TTL_S = 2 * 60 * 60  # forget a session after 2 hours of inactivity


def _prune_expired_sessions() -> None:
    """Drop sessions idle longer than the TTL (caller holds _history_lock)."""
    now = time.time()
    stale = [
        sid for sid, s in session_history.items()
        if now - s.get("last_activity", 0) > _HISTORY_TTL_S
    ]
    for sid in stale:
        del session_history[sid]
        logger.info("Cleared idle session history for %s", sid)


def _append_turn(session_id: str, role: str, content: str) -> None:
    """Append one turn to a session's transcript, trimming to the last N."""
    content = str(content or "").strip()
    if not session_id or not content:
        return
    with _history_lock:
        _prune_expired_sessions()
        sess = session_history.setdefault(
            session_id, {"turns": [], "last_activity": time.time()}
        )
        sess["turns"].append({"role": role, "content": content})
        sess["turns"] = sess["turns"][-_HISTORY_MAX_TURNS:]
        sess["last_activity"] = time.time()


def record_outcome(session_id: str, summary: str) -> None:
    """Append a one-sentence Felix summary as a 'felix' turn after execution.

    Called from the engine flow once a plan has run so the next command in the
    same session can reference what Felix just did.
    """
    _append_turn(session_id, "felix", summary)


def _conversation_block(session_id: str) -> str:
    """Render the last few prior turns as a RECENT CONVERSATION prompt block."""
    if not session_id:
        return ""
    with _history_lock:
        _prune_expired_sessions()
        sess = session_history.get(session_id)
        turns = list(sess["turns"]) if sess else []
    if not turns:
        return ""
    recent = turns[-_HISTORY_INJECT_TURNS:]
    lines = []
    for t in recent:
        speaker = "User" if t.get("role") == "user" else "Felix"
        lines.append(f"{speaker}: {t.get('content', '')}")
    return "RECENT CONVERSATION:\n" + "\n".join(lines) + "\n"


def _compose_user_text(session_id: str, voice_text: str) -> str:
    """Build the user-facing prompt text, injecting recent conversation.

    Reads prior turns FIRST (so the current command isn't duplicated), then
    records this command as a new user turn for future context.
    """
    block = _conversation_block(session_id)
    _append_turn(session_id, "user", voice_text)
    if block:
        return f"{block}Current command: {voice_text}"
    return f"User voice command: {voice_text}"

# Groq is the ONLY AI provider (Fix 6/9). GROQ_API_KEY is the only required key.
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

# Vision-capable Groq model (llama-4-scout handles image_url content).
GROQ_MODEL = os.getenv("GROQ_MODEL", "meta-llama/llama-4-scout-17b-16e-instruct")

VALID_TOOLS = (
    "notes.create_from_image",
    "gmail.draft_email",
    "browser.open_url",
    "slides.create_presentation",
    "numbers.create_spreadsheet",
    "numbers.add_expense",
    # Email reading (Phase 2)
    "gmail.read_inbox",
    "gmail.read_email",
    "gmail.reply_draft",
    # Browser reading/automation (Phase 3)
    "browser.read_page",
    "browser.fill_form",
    # Document editing (Phase 4)
    "notes.append_to_note",
    "notes.list_notes",
    "numbers.read_sheet",
    "numbers.edit_cell",
    # iOS native actions (Phase 5)
    "ios.create_reminder",
    "ios.create_note",
    "ios.open_maps",
    "ios.send_message_draft",
    # Media controls (Phase 6)
    "media.play_pause",
    "media.next_track",
    "media.previous_track",
    "media.open_spotify",
    "media.open_apple_music",
    # System control (Phase 1b)
    "system.set_volume",
    "system.set_brightness",
    "system.open_focus_settings",
    "system.lock_screen",
    "system.empty_trash",
    "system.get_battery",
    # Finder / filesystem (Phase 1c)
    "finder.open_file",
    "finder.find_file",
    "finder.move_file",
    "finder.create_folder",
    "finder.rename_file",
    "finder.show_in_finder",
    # Clipboard (Phase 1d)
    "clipboard.copy_text",
    # Calendar (Phase 1e)
    "calendar.create_event",
    "calendar.read_today",
    "calendar.read_week",
    "calendar.find_free_time",
    # Reminders (Phase 1f)
    "reminders.add_item",
    "reminders.read_list",
    "reminders.complete_item",
    # Contacts (Phase 1g)
    "contacts.find",
    # Screen awareness (Phase 1h / Phase 5)
    "screen.capture_and_describe",
    "screen.capture_and_act",
    # Web research agent (Phase 6)
    "web.search",
    "web.fetch_page",
    "web.research",
)

# Tools whose datetime args ("tomorrow at 3pm") must be normalized to ISO8601
# before execution. Maps tool -> the arg keys that hold a datetime string.
_DATETIME_ARGS = {
    "calendar.create_event": ("start_datetime",),
    "reminders.add_item": ("due_date",),
}

SYSTEM_INSTRUCTION = (
    "You are a macOS automation agent, like a hands-on coworker. You do not "
    "respond with text. You only output a JSON workflow of executable tool "
    "calls. You convert user intent (voice + an optional image) into real "
    "actions on the operating system. If an action cannot be executed, choose "
    "the closest valid tool.\n\n"
    'Output ONLY a single JSON object: {"steps": [{"tool": string, "args": {}}, ...]}\n'
    "Steps execute in order. To use a previous step's result in a later step, "
    'reference it as {{INDEX.FIELD}} inside a string arg, e.g. {{0.url}} is the '
    "URL produced by step 0. Most results expose: url, title.\n\n"
    "When an image is provided, READ IT CAREFULLY and EXTRACT its content "
    "VERBATIM to fill the document (slides bullets, sheet rows, note content). "
    "Transcribe text exactly as written — preserve every number, name, date, "
    "currency amount, email address, and unit precisely. Do NOT summarize, "
    "paraphrase, round, correct spelling, or omit anything. For receipts and "
    "tables, read every row and column and keep their order; align numbers to the "
    "right columns.\n"
    "ANTI-FABRICATION (critical for receipts): Use ONLY the merchant name, items, "
    "quantities, and prices that are ACTUALLY PRINTED in the image. NEVER guess a "
    "store from branding, NEVER substitute the e-commerce platform (e.g. do not "
    "write 'Shopify', 'Square', 'Stripe') for the real store name, and NEVER make "
    "up prices. Read each price digit-for-digit. If a field is unreadable, leave it "
    "blank ('') instead of inventing a value. Better to leave a cell empty than wrong.\n"
    "CRITICAL: Output only literal values you actually extracted. NEVER invent "
    "placeholder tokens such as {{date}}, {{merchant}}, or {{image.text}} — the "
    "ONLY allowed templating is {{N.field}} referencing a PRIOR step's url/title.\n"
    "CRITICAL: NEVER add a notes.create_from_image step just to extract text for "
    "another tool. Put the extracted image content DIRECTLY into the target "
    "tool's args — the email body, the slide bullets, the sheet rows, etc. Use "
    "notes.create_from_image ONLY when the user explicitly wants a NOTE.\n"
    "For 'draft an email from this', output exactly ONE step: gmail.draft_email "
    "with the extracted body. Keep the workflow minimal — usually one step.\n\n"
    "Available tools and their args:\n"
    "1. slides.create_presentation — Create a real Google Slides deck from the "
    'content. args: {"title": str, "slides": [{"title": str, "bullets": [str, ...]}, ...]}\n'
    "2. numbers.create_spreadsheet — Create a NEW Apple Numbers spreadsheet from "
    'the content. args: {"title": str, "headers": [str, ...], "rows": [[cell, ...], ...]}\n'
    "2b. numbers.add_expense — APPEND a receipt/expense to the user's ONE persistent "
    "Apple Numbers expense file (use this for 'add to my expense spreadsheet'). "
    "Extract date, merchant, category, amount, notes from the receipt image. "
    'args: {"rows": [[date, merchant, category, amount, notes], ...]}\n'
    "3. notes.create_from_image — Apple Notes note from extracted image text. "
    'args: {"title": str, "content": str}\n'
    "4. media.open_spotify — Open Spotify and start playback, optionally for a "
    'search query ("play X on Spotify"). args: {"query"?: str}\n'
    "4b. media.open_apple_music — Open Apple Music and play, optionally a query. "
    'args: {"query"?: str}\n'
    "4c. media.play_pause — Toggle play/pause of whatever is playing. args: {}\n"
    "4d. media.next_track — Skip to the next track. args: {}\n"
    "4e. media.previous_track — Go to the previous track. args: {}\n"
    "5. gmail.draft_email — Open a Gmail compose window in Chrome (do NOT send). "
    'args: {"to": str, "subject": str, "body": str}\n'
    "6. browser.open_url — Open Chrome at a URL. "
    'args: {"url": str}\n'
    "7. system.set_volume — Set output volume. "
    'args: {"level": 0-100}\n'
    "8. system.set_brightness — Set display brightness. "
    'args: {"level": 0-100}\n'
    "9. system.open_focus_settings — Open System Settings to the Focus pane so "
    "the user can toggle Do Not Disturb / Focus manually (macOS blocks "
    "automating this). args: {}\n"
    "10. system.lock_screen — Lock the Mac screen. args: {}\n"
    "11. system.empty_trash — Empty the Trash (irreversible). args: {}\n"
    "12. system.get_battery — Report battery percentage and charging status. args: {}\n"
    "13. finder.open_file — Spotlight-search a file and OPEN the top match. "
    'args: {"query": str}\n'
    "14. finder.find_file — Spotlight-search and RETURN the top 5 matches without "
    'opening (use to confirm which file the user meant). args: {"query": str}\n'
    "15. finder.move_file — Move a file (irreversible). "
    'args: {"source": str, "destination": str}\n'
    "16. finder.create_folder — Create a folder. args: {\"path\": str}\n"
    "17. finder.rename_file — Rename a file in place (irreversible). "
    'args: {"path": str, "new_name": str}\n'
    "18. finder.show_in_finder — Reveal a file/folder in Finder. "
    'args: {"path": str}\n'
    "For all finder tools, pass only relative paths or folder names. Never "
    "construct absolute paths. Examples: 'Felix Test', '~/Desktop/Felix Test', "
    "'Documents/Projects'. The backend will resolve the full path automatically.\n"
    "19. clipboard.copy_text — Copy text to the clipboard. args: {\"text\": str}\n"
    "20. calendar.create_event — Create a Calendar event (irreversible). "
    'args: {"title": str, "start_datetime": ISO8601 str, "duration_minutes": int, '
    '"notes"?: str, "calendar_name"?: str}. ALWAYS give start_datetime as a real '
    "absolute date/time; the user's natural-language date is normalized for you.\n"
    "21. calendar.read_today — Read today's events. args: {}\n"
    "22. calendar.read_week — Read the next 7 days of events. args: {}\n"
    "23. calendar.find_free_time — Find free slots. "
    'args: {"duration_minutes": int, "within_days": int}\n'
    "24. reminders.add_item — Add a reminder (irreversible). "
    'args: {"title": str, "list_name"?: str, "due_date"?: ISO8601 str, "notes"?: str}\n'
    "25. reminders.read_list — Read open reminders. args: {\"list_name\"?: str}\n"
    "26. reminders.complete_item — Mark a reminder complete. "
    'args: {"title": str, "list_name"?: str}\n'
    "27. contacts.find — Look up a contact's name/email/phone (use this FIRST to "
    'resolve "email my boss" before drafting). args: {"query": str}\n'
    "28. screen.capture_and_describe — Screenshot the Mac and describe what is on "
    'screen (use for "what am I looking at", "summarize this page"). args: {}\n'
    "29. screen.capture_and_act — Screenshot the Mac and act on what is visible "
    '(use for "fix this error", "what should I do here"). For filling a web form '
    "with known field selectors, prefer browser.fill_form. args: {\"instruction\": str}\n"
    "30. web.search — Search the web and return the top 5 results. "
    'args: {"query": str}\n'
    "31. web.fetch_page — Fetch a URL and return its clean text (truncated). "
    'args: {"url": str}\n'
    "32. web.research — Research a topic end-to-end (multiple searches + page "
    "fetches), synthesize with citations, and save the result as a Note. Use for "
    '"research X", "find out about X", "look up X", "what is X", "summarize X", '
    '"learn about X". args: {"topic": str, "output_format": "note"|"document"|"summary"}\n'
    "33. gmail.read_inbox — Read recent inbox emails (sender, subject, preview). "
    'args: {"count"?: int}\n'
    "34. gmail.read_email — Read the full email whose subject contains the query. "
    'args: {"subject_query": str}\n'
    "35. gmail.reply_draft — Open a pre-filled reply in Mail (do NOT send, "
    'irreversible). args: {"subject_query": str, "reply_body": str}\n'
    "36. browser.read_page — Read the current Chrome tab's title/URL/text (use "
    "for 'what's on this page', 'summarize this site'). args: {}\n"
    "37. browser.fill_form — Fill fields in the current Chrome tab and dispatch "
    'input/change events (do NOT submit, irreversible). args: {"fields": [{"selector": str, "value": str}, ...]}\n'
    "38. notes.append_to_note — Append content to a Notes note whose name matches "
    'the title; creates it if none exists. args: {"title": str, "content": str}\n'
    "39. notes.list_notes — List recent Apple Notes with dates. args: {\"count\"?: int}\n"
    "40. numbers.read_sheet — Read the frontmost (or a given) Numbers spreadsheet. "
    'args: {"file_path"?: str}\n'
    "41. numbers.edit_cell — Set one cell in the frontmost Numbers spreadsheet. "
    'args: {"row": int, "column": int, "value": str}\n'
    "42. ios.create_reminder — Create a reminder natively on the user's iPHONE "
    '(only when they say "on my phone"). args: {"title": str, "due_date"?: str}\n'
    "43. ios.create_note — Create a note on the user's iPHONE. "
    'args: {"title": str, "content": str}\n'
    "44. ios.open_maps — Open Apple Maps on the iPHONE for a search/directions. "
    'args: {"query": str}\n'
    "45. ios.send_message_draft — Open a Messages draft on the iPHONE (do NOT "
    'send, irreversible). args: {"contact": str, "message": str}\n\n'
    "Routing hints: 'turn up/down the volume' -> system.set_volume; 'brighter/"
    "dimmer' -> system.set_brightness; 'lock my mac' -> system.lock_screen; "
    "'how much battery' -> system.get_battery; 'find/open my X file' -> "
    "finder.open_file; 'schedule/add to my calendar' -> calendar.create_event; "
    "'remind me to' -> reminders.add_item; 'am I free' -> calendar.find_free_time; "
    "'what's on my screen' -> screen.capture_and_describe; 'research/look up/find "
    "out about/what is/summarize/learn about X' -> web.research.\n"
    "More routing: 'read my email/check inbox/any new emails' -> gmail.read_inbox; "
    "'read the email about X/email from X' -> gmail.read_email; 'reply to/respond "
    "to the email about X' -> gmail.reply_draft; 'what's on this page/read this "
    "page/summarize this site' -> browser.read_page; 'fill in/fill out this form' "
    "-> browser.fill_form; 'add to/append to/update my note' -> notes.append_to_note; "
    "'list my notes/what notes do I have' -> notes.list_notes; 'what's in my "
    "spreadsheet/read my sheet' -> numbers.read_sheet; 'edit cell/change row X "
    "column Y' -> numbers.edit_cell; 'play/pause/resume' -> media.play_pause; "
    "'next/skip' -> media.next_track; 'previous/go back' -> media.previous_track; "
    "'open Spotify/play X on Spotify' -> media.open_spotify; 'open Apple Music/play "
    "X on Apple Music' -> media.open_apple_music. iOS NATIVE (only when the user "
    "says 'on my phone'): 'remind me on my phone' -> ios.create_reminder; 'note on "
    "my phone' -> ios.create_note; 'directions to/navigate to/open maps' -> "
    "ios.open_maps; 'text/message X' -> ios.send_message_draft.\n\n"
    "Examples:\n"
    'User (whiteboard image): "turn this into notes" -> '
    '{"steps": [{"tool": "notes.create_from_image", "args": {"title": "...", "content": "<all text from the whiteboard>"}}]}\n'
    'User (receipt image): "add to my expense spreadsheet" -> '
    '{"steps": [{"tool": "numbers.add_expense", "args": {"rows": [["2026-06-13", "Whole Foods", "Groceries", "$42.10", "milk, eggs"]]}}]}\n'
    'User (handwritten note image): "draft an email from this" -> '
    '{"steps": [{"tool": "gmail.draft_email", "args": {"to": "", "subject": "<subject from note>", "body": "<email body from the handwriting>"}}]}\n'
    'User: "play bohemian rhapsody on spotify" -> {"steps": [{"tool": "media.open_spotify", "args": {"query": "bohemian rhapsody"}}]}\n'
    'User: "skip this song" -> {"steps": [{"tool": "media.next_track", "args": {}}]}\n'
    'User: "remind me on my phone to call mom tomorrow" -> {"steps": [{"tool": "ios.create_reminder", "args": {"title": "Call mom", "due_date": "tomorrow"}}]}\n'
    'User (image of notes): "turn this into a 3 slide presentation" -> '
    '{"steps": [{"tool": "slides.create_presentation", "args": {"title": "...", "slides": [{"title": "...", "bullets": ["...", "..."]}]}}]}\n'
    'User (image of notes): "make a deck from this and email the link to sam" -> '
    '{"steps": ['
    '{"tool": "slides.create_presentation", "args": {"title": "...", "slides": [{"title": "...", "bullets": ["..."]}]}}, '
    '{"tool": "gmail.draft_email", "args": {"to": "sam", "subject": "Deck", "body": "Here is the deck: {{0.url}}"}}'
    "]}\n"
    'User (image of a table): "make a spreadsheet from this" -> '
    '{"steps": [{"tool": "numbers.create_spreadsheet", "args": {"title": "...", "headers": ["..."], "rows": [["..."]]}}]}\n'
    "Note: Apple Numbers files are local and have NO url, so never reference "
    "{{N.url}} for a numbers step."
)


def _date_block() -> str:
    """Current date/time, computed fresh on EVERY call (Fix 1).

    The planner must resolve relative dates ("tomorrow", "next Tuesday") against
    the real clock, never against anything baked in at startup or training time.
    """
    now = datetime.now()
    today = now.strftime("%A, %B %d, %Y")
    time_str = now.strftime("%I:%M %p")
    return (
        f"Today is {today} and the current time is {time_str}. "
        "Always use these as the reference for all relative dates and times. "
        f"'Tomorrow' means the day after {today}. 'Next Tuesday' means the next "
        f"Tuesday after {today}. Never guess or assume the date. Never use any "
        "date from your training data.\n\n"
    )


# Routing rules placed prominently at the top of the prompt (Fix 5) so research
# vs. navigation intents never collide.
ROUTING_RULES = (
    "CRITICAL ROUTING RULES:\n"
    "- If the user says 'research X', 'look up X', 'find out about X', 'what is "
    "X', 'tell me about X', 'summarize X', 'learn about X' -> ALWAYS use "
    "web.research. NEVER open a browser.\n"
    "- If the user says 'open X', 'go to X', 'navigate to X', 'visit X' -> use "
    "browser.open_url.\n"
    "- NEVER use browser.open_url for research requests.\n"
    "- NEVER use web.research for navigation requests.\n"
    "- These two intents are mutually exclusive.\n\n"
)


def _system_instruction() -> str:
    """Date + routing rules + base instruction + learned user-memory (Fixes 1, 5; Phase 4).

    Assembled fresh on every call so the injected date/time is always current.
    """
    base = _date_block() + ROUTING_RULES + SYSTEM_INSTRUCTION
    ctx = memory.get_context_block()
    if ctx:
        return (
            base
            + "\n\nWHAT FELIX KNOWS ABOUT THIS USER (use to fill in defaults the "
            "user does not specify; never override what the user explicitly says):\n"
            + ctx
        )
    return base


def _mock_plan(voice_text: str, image: str) -> dict:
    """Keyword fallback so the agent still routes to real tools without the LLM.

    Cannot read the image, so document content is minimal in this mode.
    """
    logger.warning("Falling back to keyword routing (no LLM).")
    text = voice_text.strip()
    lower = text.lower()

    def one(tool, args):
        return {"steps": [{"tool": tool, "args": args}]}

    # --- New tool categories (Phase 1) — checked before the legacy branches. ---

    # Screen awareness.
    if any(k in lower for k in ("on my screen", "what am i looking", "this error", "on screen")):
        if any(k in lower for k in ("fix", "fill", "do this", "act on")):
            return one("screen.capture_and_act", {"instruction": text})
        return one("screen.capture_and_describe", {})

    # --- Expansion tool categories (Phases 2-6), before legacy branches. ---
    on_phone = "my phone" in lower or "on phone" in lower

    # Browser read/fill (before web.research + default browser).
    if "fill" in lower and ("form" in lower or "field" in lower):
        return one("browser.fill_form", {"fields": []})
    if any(k in lower for k in ("this page", "this site", "this website",
                                "current tab", "current page")):
        return one("browser.read_page", {})

    # iOS native — reminder/note require "on my phone"; maps/messages are inherent.
    if on_phone and ("remind" in lower or "reminder" in lower):
        return one("ios.create_reminder", {"title": text})
    if on_phone and ("note" in lower or "write down" in lower):
        return one("ios.create_note", {"title": "Note", "content": text})
    if any(k in lower for k in ("directions to", "navigate to", "open maps", "open map")):
        q = text
        for verb in ("directions to", "navigate to", "open maps to", "open maps", "open map"):
            if verb in lower:
                q = lower.split(verb, 1)[1].strip(" .'\"") or text
                break
        return one("ios.open_maps", {"query": q})
    if any(k in lower for k in ("send a text", "text my", "message my", "imessage",
                                "send a message to")):
        contact, message = "", ""
        for verb in ("send a text to", "send a message to", "text my", "message my", "imessage"):
            if verb in lower:
                rest = lower.split(verb, 1)[1].strip()
                parts = re.split(r"\b(?:that|saying|to say)\b", rest, maxsplit=1)
                contact = parts[0].strip(" .'\"")
                message = parts[1].strip() if len(parts) > 1 else ""
                break
        return one("ios.send_message_draft", {"contact": contact, "message": message})

    # Email reading / reply (before the generic gmail draft branch).
    if ("reply" in lower or "respond" in lower) and ("email" in lower or "mail" in lower):
        return one("gmail.reply_draft", {"subject_query": "", "reply_body": ""})
    if ("read" in lower or "open" in lower) and ("email" in lower or "mail" in lower) \
            and ("about" in lower or "from" in lower):
        q = text
        for verb in ("read the email about", "the email about", "email about", "email from"):
            if verb in lower:
                q = lower.split(verb, 1)[1].strip(" .'\"") or text
                break
        return one("gmail.read_email", {"subject_query": q})
    if any(k in lower for k in ("read my email", "check my inbox", "check inbox",
                                "any new email", "new emails", "any emails", "read my inbox")):
        return one("gmail.read_inbox", {})

    # Notes append / list (before the generic notes branch).
    if ("list" in lower and "note" in lower) or "what notes" in lower:
        return one("notes.list_notes", {})
    if any(k in lower for k in ("add to my note", "append to", "add to the note",
                                "update my note", "update the note")):
        return one("notes.append_to_note", {"title": "", "content": text})

    # Spreadsheet read / edit (before the generic numbers branches).
    if any(k in lower for k in ("edit cell", "change cell", "set cell", "update cell")):
        return one("numbers.edit_cell", {"row": 1, "column": 1, "value": text})
    if ("read" in lower or "what's in" in lower or "what is in" in lower) \
            and ("spreadsheet" in lower or "sheet" in lower):
        return one("numbers.read_sheet", {})

    # System control.
    if "lock" in lower and ("screen" in lower or "mac" in lower or "computer" in lower):
        return one("system.lock_screen", {})
    if "battery" in lower:
        return one("system.get_battery", {})
    if "empty" in lower and "trash" in lower:
        return one("system.empty_trash", {})
    if any(k in lower for k in ("do not disturb", "focus mode", "focus on",
                                "quiet mode", "silence notifications", "dnd")):
        return one("system.open_focus_settings", {})
    if "volume" in lower or "louder" in lower or "quieter" in lower:
        m = re.search(r"(\d{1,3})", lower)
        return one("system.set_volume", {"level": int(m.group(1)) if m else 50})
    if "brightness" in lower or "brighter" in lower or "dimmer" in lower:
        m = re.search(r"(\d{1,3})", lower)
        return one("system.set_brightness", {"level": int(m.group(1)) if m else 50})

    # Calendar / reminders.
    if any(k in lower for k in ("free time", "am i free", "free slot")):
        return one("calendar.find_free_time", {"duration_minutes": 30, "within_days": 7})
    if any(k in lower for k in ("my calendar", "what's on today", "agenda", "schedule today")):
        return one("calendar.read_week" if "week" in lower else "calendar.read_today", {})
    if any(k in lower for k in ("schedule", "calendar event", "add to my calendar", "book ")):
        return one("calendar.create_event", {"title": text, "start_datetime": "", "duration_minutes": 60})
    if "remind me" in lower or "reminder" in lower:
        return one("reminders.add_item", {"title": text})

    # Finder / files.
    if any(k in lower for k in ("find my", "find the file", "search for the file")):
        return one("finder.find_file", {"query": text})
    if any(k in lower for k in ("open my", "open the file", "open file")):
        return one("finder.open_file", {"query": text})

    # Contacts.
    if any(k in lower for k in ("contact", "phone number", "email address of")):
        return one("contacts.find", {"query": text})

    # Clipboard.
    if "copy" in lower and "clipboard" in lower:
        return one("clipboard.copy_text", {"text": text})

    # Web research agent.
    if any(k in lower for k in ("research", "find out about", "look up", "what is",
                                "what are", "summarize", "learn about", "tell me about")):
        topic = text
        for verb in ("research", "find out about", "look up", "what is", "what are",
                     "summarize", "learn about", "tell me about"):
            if verb in lower:
                topic = lower.split(verb, 1)[1].strip(" .'\"?") or text
                break
        return one("web.research", {"topic": topic, "output_format": "note"})

    # Google Slides.
    if any(k in lower for k in ("slide", "presentation", "deck", "powerpoint", "pitch")):
        return one("slides.create_presentation", {
            "title": text or "Presentation",
            "slides": [{"title": text or "Presentation", "bullets": []}],
        })

    # Expense file (append) — must come before the generic spreadsheet branch.
    if any(k in lower for k in ("expense", "receipt")):
        return one("numbers.add_expense", {"rows": [[text]] if text else []})

    # Apple Numbers (new spreadsheet).
    if any(k in lower for k in ("spreadsheet", "sheet", "numbers", "excel", "table")):
        return one("numbers.create_spreadsheet", {
            "title": text or "Spreadsheet",
            "headers": [],
            "rows": [],
        })

    # Media controls (Phase 6).
    if any(k in lower for k in ("next track", "next song", "skip song", "skip track",
                                "skip this")):
        return one("media.next_track", {})
    if any(k in lower for k in ("previous track", "previous song", "last song",
                                "go back a song")):
        return one("media.previous_track", {})
    if any(k in lower for k in ("pause", "resume")) and "play " not in lower:
        return one("media.play_pause", {})
    if "apple music" in lower:
        query = lower
        for verb in ("play the song", "play song", "play me", "play "):
            if verb in query:
                query = query.split(verb, 1)[1]
                break
        query = query.replace("on apple music", "").strip(" .'\"")
        return one("media.open_apple_music", {"query": query if query != lower else ""})
    if any(k in lower for k in ("play ", "spotify", "song", "music", "track")):
        query = lower
        for verb in ("play the song", "play song", "play me", "play "):
            if verb in query:
                query = query.split(verb, 1)[1]
                break
        query = query.replace("on spotify", "").strip(" .'\"") or text
        return one("media.open_spotify", {"query": query})

    # Gmail.
    if any(k in lower for k in ("email", "gmail", "draft", "compose", "send a mail")):
        return one("gmail.draft_email", {"to": "", "subject": "", "body": text})

    # Apple Notes.
    if image or any(k in lower for k in ("note", "notes", "write down", "save this", "transcribe")):
        return one("notes.create_from_image", {
            "title": "Felix Note",
            "content": "" if image else text,
        })

    # Default — browser.
    url = text
    for verb in ("open website", "go to", "open the", "open ", "navigate to", "search for"):
        if verb in lower:
            url = lower.split(verb, 1)[1].strip()
            break
    return one("browser.open_url", {"url": url or "https://google.com"})


def _strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1] if "\n" in text else text
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()
    return text


_REF = re.compile(r"\{\{\s*(\d+)\.(\w+)\s*\}\}")


def _drop_extraction_note(steps: list, voice_text: str) -> list:
    """Remove a spurious leading notes.create_from_image used only to extract
    text for a later step, folding its content into the steps that referenced it.

    The vision model sometimes inserts a notes step "to extract the image" before
    the real action (email/slides/sheets). Unless the user actually asked for a
    note, drop it and inline its extracted content where it was referenced.
    """
    lower = voice_text.lower()
    if any(k in lower for k in ("note", "notes", "write down", "save this", "jot", "transcribe")):
        return steps
    if len(steps) < 2 or steps[0].get("tool") != "notes.create_from_image":
        return steps
    if all(s.get("tool") == "notes.create_from_image" for s in steps):
        return steps  # genuinely a notes-only workflow

    nargs = steps[0].get("args", {}) or {}
    extracted = str(nargs.get("content") or nargs.get("title") or "")

    def fix(val):
        if isinstance(val, str):
            def repl(m):
                idx, field = int(m.group(1)), m.group(2)
                if idx == 0:
                    return extracted          # inline the dropped note's content
                return "{{%d.%s}}" % (idx - 1, field)  # shift later references
            return _REF.sub(repl, val)
        if isinstance(val, dict):
            return {k: fix(v) for k, v in val.items()}
        if isinstance(val, list):
            return [fix(v) for v in val]
        return val

    logger.info("Pruning spurious extraction notes step from plan.")
    return [{"tool": s["tool"], "args": fix(s.get("args", {}))} for s in steps[1:]]


_CONJUNCTIONS = (" and ", " then ", " also ", " after ", " plus ", "&", ", then")

# Ordered (specific -> general) keyword groups mapping intent to a tool.
_INTENT_KEYWORDS = [
    ("screen.capture_and_act", ("fix this error", "act on my screen", "what's wrong on screen")),
    ("screen.capture_and_describe", ("on my screen", "what am i looking", "on screen")),
    # Browser reading/automation (Phase 3) — before web.research so "summarize
    # this site/page" stays on the current tab, and before browser.open_url.
    ("browser.fill_form", ("fill in this form", "fill out the form", "fill the form",
                           "fill in the form")),
    ("browser.read_page", ("this page", "this site", "this website", "current tab",
                           "read this page", "summarize this site",
                           "summarize this page", "what's on this page")),
    ("system.lock_screen", ("lock my mac", "lock the screen", "lock screen")),
    ("system.get_battery", ("battery",)),
    ("system.empty_trash", ("empty trash", "empty the trash")),
    ("system.open_focus_settings", ("do not disturb", "focus mode", "focus on",
                                    "quiet mode", "silence notifications", "dnd")),
    ("system.set_volume", ("volume", "louder", "quieter", "mute")),
    ("system.set_brightness", ("brightness", "brighter", "dimmer")),
    # iOS native actions (Phase 5) — before the Mac calendar/reminders/notes
    # equivalents. Reminder/note routes require "on my phone".
    ("ios.create_reminder", ("remind me on my phone", "reminder on my phone")),
    ("ios.create_note", ("note on my phone", "save this to my phone")),
    ("ios.open_maps", ("directions to", "navigate to", "open maps", "open map")),
    ("ios.send_message_draft", ("send a text", "text my", "message my", "imessage",
                                "send a message to", "send a message")),
    ("calendar.find_free_time", ("free time", "am i free", "free slot")),
    ("calendar.read_today", ("my agenda", "schedule today", "what's on today")),
    ("calendar.create_event", ("schedule", "calendar event", "book ")),
    ("reminders.complete_item", ("mark done", "complete the reminder", "check off")),
    ("reminders.add_item", ("remind me", "reminder")),
    ("contacts.find", ("phone number", "email address of", "contact info")),
    # Email reading/reply (Phase 2) — before the generic gmail.draft_email.
    ("gmail.reply_draft", ("reply to the email", "respond to the email", "reply to that email")),
    ("gmail.read_email", ("read the email", "email from", "email about", "open the email")),
    ("gmail.read_inbox", ("read my email", "check my inbox", "check inbox",
                          "any new email", "new emails", "read my inbox", "any emails")),
    ("web.research", ("research", "find out about", "look up", "what is", "what are",
                      "summarize", "learn about", "tell me about")),
    ("finder.find_file", ("find my", "find the file")),
    ("finder.open_file", ("open my", "open the file")),
    ("clipboard.copy_text", ("copy to clipboard",)),
    ("gmail.draft_email", ("email", "gmail", "draft", "compose", "send a mail")),
    # Spreadsheet read/edit (Phase 4) — before add_expense/create_spreadsheet.
    ("numbers.edit_cell", ("edit cell", "change cell", "set cell", "edit the cell",
                           "update cell")),
    ("numbers.read_sheet", ("read my sheet", "read my spreadsheet", "what's in my spreadsheet",
                            "what's in my sheet", "open my spreadsheet")),
    ("numbers.add_expense", ("expense", "receipt")),
    ("numbers.create_spreadsheet", ("spreadsheet", "sheet", "numbers", "excel", "table")),
    ("slides.create_presentation", ("slide", "presentation", "deck", "powerpoint", "pitch")),
    # Media controls (Phase 6) — replaces spotify.play_song.
    ("media.next_track", ("next track", "next song", "skip song", "skip track",
                          "skip this song")),
    ("media.previous_track", ("previous track", "previous song", "last song",
                              "go back a song")),
    ("media.play_pause", ("pause music", "pause the music", "resume music",
                          "play pause", "toggle playback")),
    ("media.open_apple_music", ("apple music",)),
    ("media.open_spotify", ("spotify", "play ", "song", "music", "track")),
    # Notes append/list (Phase 4) — before the generic notes.create_from_image.
    ("notes.list_notes", ("list my notes", "what notes", "show my notes")),
    ("notes.append_to_note", ("add to my note", "append to", "add to the note",
                              "update my note", "update the note")),
    ("notes.create_from_image", ("note", "notes", "write down", "save this", "jot", "transcribe")),
    ("browser.open_url", ("open website", "go to", ".com", ".org", ".io", "website", "url", "browser")),
]


def _intent_for(lower: str):
    for tool, keys in _INTENT_KEYWORDS:
        if any(k in lower for k in keys):
            return tool
    return None


def _args_for_intent(intent: str, steps: list, voice_text: str) -> dict:
    """Build args for the intended tool, reusing LLM-extracted content."""
    def reuse(tool):
        for s in steps:
            if s.get("tool") == tool and s.get("args"):
                return s["args"]
        return None

    def field(tool, key):
        for s in steps:
            if s.get("tool") == tool:
                v = s.get("args", {}).get(key)
                if v:
                    return v
        return None

    if intent == "gmail.draft_email":
        return reuse(intent) or {
            "to": "",
            "subject": "",
            "body": field("notes.create_from_image", "content") or "",
        }
    if intent == "notes.create_from_image":
        return reuse(intent) or {
            "title": "Felix Note",
            "content": field("gmail.draft_email", "body") or "",
        }
    # For the remaining tools, reuse the LLM args or fall back to keyword routing.
    return reuse(intent) or _mock_plan(voice_text, "")["steps"][0]["args"]


def _enforce_single_intent(steps: list, voice_text: str) -> list:
    """For single-intent commands, force the tool the keywords clearly indicate.

    The vision model is unreliable at routing when an image is present (it often
    defaults to notes). When the command has no conjunction, trust the keyword
    intent and reuse any content the model extracted.
    """
    lower = f" {voice_text.lower()} "
    if any(c in lower for c in _CONJUNCTIONS):
        return steps  # genuine multi-step — trust the LLM plan
    intent = _intent_for(lower)
    if intent is None:
        return steps[:1] if steps else steps
    if steps and steps[0].get("tool") == intent:
        return steps[:1]
    return [{"tool": intent, "args": _args_for_intent(intent, steps, voice_text)}]


_RESEARCH_KEYWORDS = (
    "research", "look up", "find out about", "what is", "tell me about",
    "summarize", "learn about", "explain",
)
_NAVIGATION_KEYWORDS = (
    "open", "go to", "navigate", "visit", "browse to",
)


def _enforce_research_routing(steps: list, voice_text: str) -> list:
    """Force web.research for research requests, dropping browser steps (Fix 5).

    If the command clearly asks to research/look up something AND contains no
    navigation verb, the plan must use web.research and never browser.open_url.
    """
    lower = voice_text.lower()
    has_research = any(k in lower for k in _RESEARCH_KEYWORDS)
    has_navigation = any(k in lower for k in _NAVIGATION_KEYWORDS)
    if not (has_research and not has_navigation):
        return steps

    # Strip any browser.open_url steps the model added for a research request.
    cleaned = [s for s in steps if s.get("tool") != "browser.open_url"]
    if not any(s.get("tool") == "web.research" for s in cleaned):
        topic = voice_text.strip()
        for verb in _RESEARCH_KEYWORDS:
            if verb in lower:
                topic = lower.split(verb, 1)[1].strip(" .'\"?") or voice_text.strip()
                break
        cleaned.insert(0, {
            "tool": "web.research",
            "args": {"topic": topic, "output_format": "note"},
        })
        logger.info("Forced web.research routing for research request.")
    return cleaned


def _normalize_datetimes(steps: list) -> list:
    """Convert natural-language date/time args to ISO8601 before execution.

    The vision model usually emits a real ISO datetime, but when it passes a
    phrase like "tomorrow at 3pm" we parse it with dateparser (relative to now,
    preferring future dates) so calendar/reminder tools receive a clean ISO
    string. Unparseable or already-ISO values are left untouched.
    """
    try:
        import dateparser
    except ImportError:
        logger.warning("dateparser not installed; skipping date normalization.")
        return steps

    settings = {"PREFER_DATES_FROM": "future", "RETURN_AS_TIMEZONE_AWARE": False}
    for step in steps:
        keys = _DATETIME_ARGS.get(step.get("tool"))
        if not keys:
            continue
        args = step.get("args", {})
        for key in keys:
            raw = args.get(key)
            if not isinstance(raw, str) or not raw.strip():
                continue
            # Skip values that are already strict ISO8601.
            try:
                from datetime import datetime
                datetime.fromisoformat(raw.replace("Z", "+00:00"))
                continue
            except ValueError:
                pass
            # dateparser handles most phrasings but stumbles on a few (e.g.
            # "next monday 9am"); retry with light cleanups before giving up.
            candidates = [raw, raw.replace("next ", ""), raw.replace(" at ", " ")]
            parsed = None
            for cand in candidates:
                parsed = dateparser.parse(cand, settings=settings)
                if parsed:
                    break
            if parsed:
                args[key] = parsed.isoformat()
                logger.info("Normalized %s %r -> %s", key, raw, args[key])
            else:
                logger.warning("Could not parse %s value %r", key, raw)
    return steps


def _coerce_plan(data: dict, voice_text: str, image: str) -> dict:
    """Validate LLM output into a list of known tool steps, or fall back."""
    # Accept {"steps":[...]}, a bare [...], or a single {"tool",...}.
    if isinstance(data, list):
        raw_steps = data
    elif isinstance(data, dict) and "steps" in data:
        raw_steps = data.get("steps") or []
    elif isinstance(data, dict) and "tool" in data:
        raw_steps = [data]
    else:
        raw_steps = []

    steps = []
    for s in raw_steps:
        if not isinstance(s, dict):
            continue
        tool = str(s.get("tool", "")).strip()
        args = s.get("args") or {}
        if not isinstance(args, dict):
            args = {}
        if tool in VALID_TOOLS:
            steps.append({"tool": tool, "args": args})
        else:
            logger.warning("Skipping unknown tool '%s' from LLM plan.", tool)

    if not steps:
        logger.warning("LLM produced no valid steps; using fallback.")
        return _mock_plan(voice_text, image)
    steps = _drop_extraction_note(steps, voice_text)
    steps = _enforce_single_intent(steps, voice_text)
    steps = _enforce_research_routing(steps, voice_text)
    steps = _normalize_datetimes(steps)
    return {"steps": steps}


def _call_groq(voice_text: str, image: str, user_text: str) -> dict:
    from groq import Groq

    client = Groq(api_key=GROQ_API_KEY)

    user_content = [
        {
            "type": "text",
            "text": (
                f"{user_text}\n\n"
                "Output ONLY the JSON workflow. No explanations, no markdown."
            ),
        }
    ]

    if image:
        data_url = image if image.startswith("data:") else f"data:image/jpeg;base64,{image}"
        try:
            base64.b64decode(image.split(",", 1)[1] if "," in image else image)
            user_content.append(
                {"type": "image_url", "image_url": {"url": data_url}}
            )
        except Exception as e:
            logger.warning("Failed to decode base64 image for Groq (%s)", e)

    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[
            {"role": "system", "content": _system_instruction()},
            {"role": "user", "content": user_content},
        ],
        temperature=0,
        response_format={"type": "json_object"},
    )

    raw = _strip_fences(response.choices[0].message.content or "")
    data = json.loads(raw)
    return _coerce_plan(data, voice_text, image)


def parse_plan(voice_text: str, image: str, session_id: str = "") -> dict:
    """Turn voice + image into an ordered workflow {"steps": [...]}.

    Uses Groq (the only provider), then the keyword fallback. When a session_id
    is provided, recent conversation turns are injected so follow-up commands
    like "do that again" or "change the time to 3pm" have context (Phase 3). The
    current command is recorded once here.
    """
    user_text = _compose_user_text(session_id, voice_text)

    if GROQ_API_KEY:
        try:
            return _call_groq(voice_text, image, user_text)
        except Exception as exc:
            logger.warning("Groq call failed (%s); using keyword fallback.", exc)

    return _mock_plan(voice_text, image)
