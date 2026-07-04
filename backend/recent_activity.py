"""Short-term "recent activity" memory — what Lumis just created or touched.

Distinct from memory.py (durable preferences): this is working memory. Each
entry is an artifact the user might refer back to in conversation shortly
after ("send that draft", "add a row to it") — its kind, a REAL identifier,
a short description, an optional URL, and when it happened. Entries expire
after RECENT_TTL_S and the list is capped per user, so this never resurfaces
something from days ago as if it were just made (the permanent record of what
happened lives in the action history / Past Chats).

Recording is a side effect of every successful tool result (see
record_from_result, called from the agent's execute path) — individual tools
don't have to remember to wire it up.

Standard-library sqlite3 only, sharing db.DB_PATH like connections.py.
"""
import logging
import sqlite3
import time
from typing import List, Optional

import db

logger = logging.getLogger("lumis.recent_activity")

# How long an artifact stays "the thing I just made" in conversation.
RECENT_TTL_S = 3 * 60 * 60
# Working memory, not a log — only the newest few entries per user survive.
MAX_PER_USER = 10

_SCHEMA = """
CREATE TABLE IF NOT EXISTS recent_activity (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     TEXT NOT NULL,
    kind        TEXT NOT NULL,
    ref         TEXT NOT NULL,
    description TEXT NOT NULL,
    url         TEXT,
    created_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_recent_user_time
    ON recent_activity (user_id, created_at DESC);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_recent_activity() -> None:
    with _connect() as conn:
        conn.executescript(_SCHEMA)
    logger.info("Recent-activity table ready at %s", db.DB_PATH)


def record(user_id: str, kind: str, ref: str, description: str,
           url: Optional[str] = None) -> None:
    """Remember one artifact. Same (user, kind, ref) replaces the old entry so
    editing a document refreshes it rather than duplicating it."""
    if not user_id or not ref:
        return
    now = time.time()
    with _connect() as conn:
        conn.execute(
            "DELETE FROM recent_activity WHERE user_id = ? AND kind = ? AND ref = ?",
            (user_id, kind, ref),
        )
        conn.execute(
            "INSERT INTO recent_activity (user_id, kind, ref, description, url, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (user_id, kind, ref, description[:300], url, now),
        )
        # Expire old entries and cap the list (newest MAX_PER_USER survive).
        conn.execute(
            "DELETE FROM recent_activity WHERE user_id = ? AND created_at < ?",
            (user_id, now - RECENT_TTL_S),
        )
        conn.execute(
            "DELETE FROM recent_activity WHERE user_id = ? AND id NOT IN ("
            "  SELECT id FROM recent_activity WHERE user_id = ? "
            "  ORDER BY created_at DESC LIMIT ?)",
            (user_id, user_id, MAX_PER_USER),
        )
        conn.commit()
    logger.info("Recent activity: %s %s (%s)", kind, ref, description[:60])


def get_recent(user_id: str) -> List[dict]:
    """Unexpired entries, newest first."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT kind, ref, description, url, created_at FROM recent_activity "
            "WHERE user_id = ? AND created_at >= ? ORDER BY created_at DESC",
            (user_id, time.time() - RECENT_TTL_S),
        ).fetchall()
    return [dict(r) for r in rows]


def _age(ts: float) -> str:
    mins = max(0, int((time.time() - ts) / 60))
    if mins < 1:
        return "just now"
    if mins < 60:
        return f"{mins} min ago"
    hours = mins // 60
    return f"{hours} hour{'s' if hours != 1 else ''} ago"


def context_block(user_id: str) -> str:
    """Render recent activity for the agent's first message ('' if none).

    Each line carries the REAL id so the agent can act on the existing
    artifact instead of creating a duplicate.
    """
    entries = get_recent(user_id)
    if not entries:
        return ""
    lines = [
        f"- [{_age(e['created_at'])}] {e['kind']} (id: {e['ref']}): {e['description']}"
        for e in entries
    ]
    return (
        "\n\nRECENT ACTIVITY (things Lumis just created or touched for this user — "
        "when the command references one of these ambiguously ('that draft', 'the "
        "doc I just made', 'add to it'), act on the EXISTING artifact via its real "
        "id instead of creating a new one; ignore entries that clearly don't "
        "match):\n" + "\n".join(lines)
    )


# --------------------------------------------------------------------------- #
# Automatic extraction from tool results
# --------------------------------------------------------------------------- #
# tool -> (kind, id key in result.data, description builder). Tools that only
# read (read_inbox, read_sheet, search, screenshot, …) intentionally have no
# entry — recent activity is things the user might act on again, not views.
def _email_desc(args: dict, data: dict) -> str:
    to = str(data.get("to") or args.get("to") or "").strip()
    subject = str(args.get("subject") or "").strip()
    who = to if to else "NO RECIPIENT yet"
    return f"email draft to {who}, subject: {subject or '(none)'}"


_RECORDERS = {
    "gmail.draft_email":        ("email_draft",  "draft_id",
                                 _email_desc),
    "gmail.update_draft":       ("email_draft",  "draft_id",
                                 _email_desc),
    "docs.create_document":     ("google_doc",   "document_id",
                                 lambda a, d: f"Google Doc '{a.get('title') or 'Untitled'}'"),
    "docs.append_text":         ("google_doc",   "document_id",
                                 lambda a, d: "Google Doc (appended text)"),
    "sheets.create_spreadsheet": ("spreadsheet", "spreadsheet_id",
                                 lambda a, d: f"spreadsheet '{a.get('title') or 'Untitled'}'"),
    "sheets.add_row":           ("spreadsheet",  "spreadsheet_id",
                                 lambda a, d: "spreadsheet (added a row)"),
    "sheets.edit_cell":         ("spreadsheet",  "spreadsheet_id",
                                 lambda a, d: "spreadsheet (edited a cell)"),
    "calendar.create_event":    ("calendar_event", "event_id",
                                 lambda a, d: f"calendar event '{a.get('title') or 'Event'}' at {a.get('start_datetime') or '?'}"),
    "tasks.create_task":        ("task",         "task_id",
                                 lambda a, d: f"task '{a.get('title') or ''}'"),
    "notion.create_page":       ("notion_page",  "url",
                                 lambda a, d: f"Notion page '{a.get('title') or ''}'"),
}


def record_from_result(user_id: str, tool: str, args: dict, result: dict) -> None:
    """Side effect of every successful tool call (called by the agent).

    Known creating/modifying tools record via _RECORDERS; anything else that
    returned a data id/url with a create/add/append/update verb records
    generically, so new tools participate without extra wiring.
    """
    if not result or result.get("status") != "success":
        return
    data = result.get("data") or {}
    args = args or {}

    spec = _RECORDERS.get(tool)
    if spec:
        kind, id_key, describe = spec
        ref = str(data.get(id_key) or data.get("url") or "").strip()
        if ref:
            record(user_id, kind, ref, describe(args, data), data.get("url"))
        return

    # Generic fallback: a mutating verb + a real identifier in the result.
    verb = tool.split(".", 1)[-1]
    if any(verb.startswith(v) for v in ("create", "add", "append", "update",
                                        "post", "send", "move", "edit")):
        ref = str(
            next((data[k] for k in data if str(k).endswith("_id") and data[k]), "")
            or data.get("url") or ""
        ).strip()
        if ref:
            desc = str(result.get("message") or result.get("title") or tool)[:200]
            record(user_id, tool.split(".", 1)[0], ref, desc, data.get("url"))
