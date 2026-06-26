"""SQLite action-history store for Felix (Phase 2).

Why this exists: trust comes from being able to see and undo what Felix did.
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

logger = logging.getLogger("felix.db")

DB_PATH = os.path.expanduser(
    os.getenv("FELIX_DB_PATH", os.path.join(os.path.dirname(__file__), "actions.db"))
)

# On hosted deploys (Railway) FELIX_DB_PATH points at a mounted volume like
# /app/data/actions.db whose parent may not exist yet — create it up front.
_db_dir = os.path.dirname(DB_PATH)
if _db_dir:
    os.makedirs(_db_dir, exist_ok=True)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS actions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT,
    timestamp       REAL,
    tool_name       TEXT,
    args_json       TEXT,
    result_json     TEXT,
    undo_available  INTEGER NOT NULL DEFAULT 0,
    undo_script     TEXT
);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create the actions table if it does not exist. Safe to call repeatedly."""
    with _connect() as conn:
        conn.executescript(_SCHEMA)
    logger.info("Action history DB ready at %s", DB_PATH)


def record_action(session_id: str, tool_name: str, args: dict) -> int:
    """Insert a pre-execution row and return its id.

    Called before the tool runs so the attempt is logged even if it fails.
    """
    with _connect() as conn:
        cur = conn.execute(
            "INSERT INTO actions (session_id, timestamp, tool_name, args_json, "
            "result_json, undo_available, undo_script) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
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


def get_history(limit: int = 50) -> list[dict]:
    """Return the most recent actions, newest first."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM actions ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


def get_action(action_id: int) -> Optional[dict]:
    """Return one action row including its undo_script, or None."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM actions WHERE id = ?", (action_id,)
        ).fetchone()
    if row is None:
        return None
    data = _row_to_dict(row)
    data["undo_script"] = row["undo_script"]
    return data


def mark_undone(action_id: int) -> None:
    """Disable further undo for an action once it has been undone."""
    with _connect() as conn:
        conn.execute(
            "UPDATE actions SET undo_available = 0 WHERE id = ?", (action_id,)
        )
