"""SQLite action-history store for Lumis (Phase 2).

Why this exists: trust comes from being able to see and undo what Lumis did.
Every tool execution is logged here *before* it runs (so even a crash leaves a
trail) and updated with its result + undo info afterward. Powers GET /history
and POST /undo/{id}.

Standard-library only (sqlite3) per the Phase 1/2 constraints. A fresh
connection is opened per call so it is safe to use from the event loop and from
executor threads without sharing handles.
"""
import json
import logging
import os
import sqlite3
import time
from typing import Optional

logger = logging.getLogger("lumis.db")

DB_PATH = os.path.expanduser(
    os.getenv("LUMIS_DB_PATH", os.path.join(os.path.dirname(__file__), "actions.db"))
)

# On hosted deploys (Railway) LUMIS_DB_PATH points at a mounted volume like
# /app/data/actions.db whose parent may not exist yet — create it up front.
_db_dir = os.path.dirname(DB_PATH)
if _db_dir:
    os.makedirs(_db_dir, exist_ok=True)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS actions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         TEXT,
    session_id      TEXT,
    timestamp       REAL,
    tool_name       TEXT,
    args_json       TEXT,
    result_json     TEXT,
    undo_available  INTEGER NOT NULL DEFAULT 0,
    undo_script     TEXT
);
"""

# History rows with no owner (legacy global rows, or background tasks without an
# authenticated user) live under this sentinel and are hidden from per-user reads.
GLOBAL_USER = "_global"


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create the actions table if it does not exist. Safe to call repeatedly."""
    with _connect() as conn:
        conn.executescript(_SCHEMA)
        # Migrate older databases that predate per-account scoping.
        cols = {row["name"] for row in conn.execute("PRAGMA table_info(actions)")}
        if "user_id" not in cols:
            conn.execute("ALTER TABLE actions ADD COLUMN user_id TEXT")
        conn.commit()
    logger.info("Action history DB ready at %s", DB_PATH)


def record_action(session_id: str, tool_name: str, args: dict,
                  user_id: str = GLOBAL_USER) -> int:
    """Insert a pre-execution row and return its id.

    Called before the tool runs so the attempt is logged even if it fails.
    `user_id` scopes the row to an account so each user only sees their own
    history (and the Mac, signed into the same account, sees it too).
    """
    with _connect() as conn:
        cur = conn.execute(
            "INSERT INTO actions (user_id, session_id, timestamp, tool_name, args_json, "
            "result_json, undo_available, undo_script) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                user_id,
                session_id,
                time.time(),
                tool_name,
                json.dumps(args, default=str),
                None,
                0,
                None,
            ),
        )
        return int(cur.lastrowid)


def complete_action(
    action_id: int,
    result: dict,
    undo_available: bool,
    undo_script: Optional[str],
) -> None:
    """Fill in a row's result + undo info after the tool has executed."""
    with _connect() as conn:
        conn.execute(
            "UPDATE actions SET result_json = ?, undo_available = ?, undo_script = ? "
            "WHERE id = ?",
            (
                json.dumps(result, default=str),
                1 if undo_available else 0,
                undo_script,
                action_id,
            ),
        )


def _row_to_dict(row: sqlite3.Row) -> dict:
    """Shape a DB row into the JSON returned by GET /history."""
    result = json.loads(row["result_json"]) if row["result_json"] else None
    return {
        "id": row["id"],
        "session_id": row["session_id"],
        "timestamp": row["timestamp"],
        "tool_name": row["tool_name"],
        "args": json.loads(row["args_json"]) if row["args_json"] else {},
        "result": result,
        "status": (result or {}).get("status", "pending"),
        "message": (result or {}).get("message", ""),
        "title": (result or {}).get("title", ""),
        "summary": (result or {}).get("summary", ""),
        "undo_available": bool(row["undo_available"]),
    }


def get_history(limit: int = 50, user_id: Optional[str] = None) -> list[dict]:
    """Return the most recent actions, newest first.

    When `user_id` is given, only that account's actions are returned.
    """
    with _connect() as conn:
        if user_id is None:
            rows = conn.execute(
                "SELECT * FROM actions ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM actions WHERE user_id = ? ORDER BY id DESC LIMIT ?",
                (user_id, limit),
            ).fetchall()
    return [_row_to_dict(r) for r in rows]


def get_action(action_id: int, user_id: Optional[str] = None) -> Optional[dict]:
    """Return one action row including its undo_script, or None.

    When `user_id` is given, the row must belong to that account.
    """
    with _connect() as conn:
        if user_id is None:
            row = conn.execute(
                "SELECT * FROM actions WHERE id = ?", (action_id,)
            ).fetchone()
        else:
            row = conn.execute(
                "SELECT * FROM actions WHERE id = ? AND user_id = ?",
                (action_id, user_id),
            ).fetchone()
    if row is None:
        return None
    data = _row_to_dict(row)
    data["undo_script"] = row["undo_script"]
    data["user_id"] = row["user_id"]
    data["session_id"] = row["session_id"]
    return data


def mark_undone(action_id: int) -> None:
    """Disable further undo for an action once it has been undone."""
    with _connect() as conn:
        conn.execute(
            "UPDATE actions SET undo_available = 0 WHERE id = ?", (action_id,)
        )


def delete_user_actions(user_id: str) -> None:
    """Remove every action row owned by this account (account deletion)."""
    with _connect() as conn:
        conn.execute("DELETE FROM actions WHERE user_id = ?", (user_id,))
        conn.commit()
