"""Account connection store for the Chrome extension cookie-sync flow.

Two things are persisted per Lumis user:
  * their Browserbase persistent-context id (so all future cloud-browser
    sessions reuse the same logged-in cookies), and
  * the set of services they have connected (Gmail, Notion, ...), surfaced by
    GET /connect/status so the extension can show connected/not-connected state.

Standard-library sqlite3 only, sharing db.DB_PATH with the rest of the backend.
A fresh connection is opened per call (safe from the event loop and executors).
"""
import logging
import os
import sqlite3
import time
from typing import List, Optional

import db

logger = logging.getLogger("lumis.connections")

# A service is only "connected" for tool gating if cookies were synced within
# this window. Status still reports stale services so the UI can nudge re-sync.
FRESH_WITHIN_S = int(os.getenv("CONNECTION_FRESH_S", str(24 * 60 * 60)))

_SCHEMA = """
CREATE TABLE IF NOT EXISTS browser_contexts (
    user_id     TEXT PRIMARY KEY,
    context_id  TEXT NOT NULL,
    created_at  REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS connected_services (
    user_id      TEXT NOT NULL,
    service      TEXT NOT NULL,
    connected_at REAL NOT NULL,
    PRIMARY KEY (user_id, service)
);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_connections() -> None:
    """Create the connection tables. Safe to call repeatedly."""
    with _connect() as conn:
        conn.executescript(_SCHEMA)
    logger.info("Connection tables ready at %s", db.DB_PATH)


# --------------------------------------------------------------------------- #
# Browserbase context mapping
# --------------------------------------------------------------------------- #
def get_context_id(user_id: str) -> Optional[str]:
    with _connect() as conn:
        row = conn.execute(
            "SELECT context_id FROM browser_contexts WHERE user_id = ?", (user_id,)
        ).fetchone()
    return row["context_id"] if row else None


def set_context_id(user_id: str, context_id: str) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT INTO browser_contexts (user_id, context_id, created_at) "
            "VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET context_id = excluded.context_id",
            (user_id, context_id, time.time()),
        )
        conn.commit()


# --------------------------------------------------------------------------- #
# Connected services
# --------------------------------------------------------------------------- #
def add_connected_service(user_id: str, service: str) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT INTO connected_services (user_id, service, connected_at) "
            "VALUES (?, ?, ?) ON CONFLICT(user_id, service) DO UPDATE SET connected_at = excluded.connected_at",
            (user_id, service, time.time()),
        )
        conn.commit()


def get_connection_details(user_id: str) -> List[dict]:
    """Each connected service with when its cookies were last synced.

    `connected_at` is refreshed on every successful cookie sync, so it is the
    honest "last synced" timestamp the status endpoint reports. Includes a
    `fresh` flag so clients can distinguish live vs stale connections.
    """
    now = time.time()
    with _connect() as conn:
        rows = conn.execute(
            "SELECT service, connected_at FROM connected_services "
            "WHERE user_id = ? ORDER BY connected_at",
            (user_id,),
        ).fetchall()
    out = []
    for r in rows:
        age = now - float(r["connected_at"] or 0)
        out.append({
            "service": r["service"],
            "last_synced_at": r["connected_at"],
            "fresh": age <= FRESH_WITHIN_S,
            "stale": age > FRESH_WITHIN_S,
        })
    return out


def get_connected_services(user_id: str, *, fresh_only: bool = True) -> List[str]:
    """Services available for tool gating.

    By default only returns services synced within FRESH_WITHIN_S so expired
    cookie sessions are not treated as connected forever.
    """
    now = time.time()
    with _connect() as conn:
        rows = conn.execute(
            "SELECT service, connected_at FROM connected_services "
            "WHERE user_id = ? ORDER BY connected_at",
            (user_id,),
        ).fetchall()
    out = []
    for r in rows:
        if fresh_only and (now - float(r["connected_at"] or 0)) > FRESH_WITHIN_S:
            continue
        out.append(r["service"])
    return out


def remove_connected_service(user_id: str, service: str) -> None:
    with _connect() as conn:
        conn.execute(
            "DELETE FROM connected_services WHERE user_id = ? AND service = ?",
            (user_id, service),
        )
        conn.commit()


def delete_user_data(user_id: str) -> None:
    """Wipe Browserbase context + connected-service rows for account deletion."""
    with _connect() as conn:
        conn.execute("DELETE FROM connected_services WHERE user_id = ?", (user_id,))
        conn.execute("DELETE FROM browser_contexts WHERE user_id = ?", (user_id,))
        conn.commit()
