"""Mac <-> iPhone linking for Lumis.

One iPhone links to exactly one Mac (pairing keyed by user id). The Mac asks for
a short code, shows it; the iPhone (authenticated) submits the code to pair. The
Mac sends heartbeats so the phone can tell whether it is currently online.

Standard-library SQLite, shares the same DB file as auth/history.
"""
import logging
import os
import secrets
import sqlite3
import time
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

import db
from auth import current_user

logger = logging.getLogger("lumis.linking")

router = APIRouter(prefix="/link", tags=["linking"])

CODE_TTL = 10 * 60          # codes valid for 10 minutes
ONLINE_WINDOW = 30          # seconds since last heartbeat to count as online
# Unambiguous alphabet (no O/0, I/1) for a 6-char code.
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS link_codes (
    code        TEXT PRIMARY KEY,
    mac_id      TEXT NOT NULL,
    mac_name    TEXT,
    created_at  REAL NOT NULL,
    expires_at  REAL NOT NULL,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS pairings (
    user_id        TEXT PRIMARY KEY,
    mac_id         TEXT NOT NULL,
    mac_name       TEXT,
    linked_at      REAL NOT NULL,
    last_heartbeat REAL NOT NULL
);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_linking() -> None:
    with _connect() as conn:
        conn.executescript(_SCHEMA)
    logger.info("Linking tables ready at %s", db.DB_PATH)


def _gen_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(6))


# --------------------------------------------------------------------------- #
# Request models
# --------------------------------------------------------------------------- #
class GenerateBody(BaseModel):
    mac_id: Optional[str] = None
    mac_name: str = "Mac"


class PairBody(BaseModel):
    code: str


class HeartbeatBody(BaseModel):
    mac_id: str
    mac_name: Optional[str] = None


# --------------------------------------------------------------------------- #
# Mac-facing endpoints (no user auth; identified by mac_id)
# --------------------------------------------------------------------------- #
@router.post("/generate")
async def generate(body: GenerateBody):
    """Mac requests a fresh 6-char pairing code (valid 10 minutes)."""
    mac_id = body.mac_id or str(uuid.uuid4())
    now = time.time()
    code = _gen_code()
    with _connect() as conn:
        # Avoid the rare collision on the active code space.
        while conn.execute(
            "SELECT 1 FROM link_codes WHERE code = ? AND expires_at > ?", (code, now)
        ).fetchone():
            code = _gen_code()
        conn.execute(
            "INSERT OR REPLACE INTO link_codes (code, mac_id, mac_name, created_at, expires_at, used) "
            "VALUES (?, ?, ?, ?, ?, 0)",
            (code, mac_id, body.mac_name, now, now + CODE_TTL),
        )
        conn.commit()
    return {"code": code, "expiresAt": now + CODE_TTL, "macId": mac_id}


@router.post("/heartbeat")
async def heartbeat(body: HeartbeatBody):
    """Mac pings to stay 'online'. Updates the pairing's last_heartbeat."""
    now = time.time()
    with _connect() as conn:
        cur = conn.execute(
            "UPDATE pairings SET last_heartbeat = ?, mac_name = COALESCE(?, mac_name) "
            "WHERE mac_id = ?",
            (now, body.mac_name, body.mac_id),
        )
        conn.commit()
    return {"success": True, "paired": cur.rowcount > 0}


@router.get("/mac/{mac_id}")
async def mac_status(mac_id: str):
    """Mac polls this to learn when a phone has paired with it."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM pairings WHERE mac_id = ?", (mac_id,)
        ).fetchone()
    return {"linked": row is not None}


# --------------------------------------------------------------------------- #
# iPhone-facing endpoints (require auth)
# --------------------------------------------------------------------------- #
@router.post("/pair")
async def pair(body: PairBody, user: dict = Depends(current_user)):
    code = body.code.strip().upper()
    now = time.time()
    with _connect() as conn:
        row = conn.execute("SELECT * FROM link_codes WHERE code = ?", (code,)).fetchone()
        if not row or row["used"] or row["expires_at"] < now:
            raise HTTPException(status_code=400, detail="Invalid or expired code. Try again.")
        conn.execute("UPDATE link_codes SET used = 1 WHERE code = ?", (code,))
        conn.execute(
            "INSERT OR REPLACE INTO pairings (user_id, mac_id, mac_name, linked_at, last_heartbeat) "
            "VALUES (?, ?, ?, ?, ?)",
            (user["id"], row["mac_id"], row["mac_name"], now, now),
        )
        conn.commit()
    return {"macId": row["mac_id"], "macName": row["mac_name"]}


@router.delete("/unpair")
async def unpair(user: dict = Depends(current_user)):
    with _connect() as conn:
        conn.execute("DELETE FROM pairings WHERE user_id = ?", (user["id"],))
        conn.commit()
    return {"success": True}


@router.get("/status")
async def status(user: dict = Depends(current_user)):
    now = time.time()
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM pairings WHERE user_id = ?", (user["id"],)
        ).fetchone()
    if not row:
        return {"linked": False, "macId": None, "macName": None,
                "macOnline": False, "lastSeen": None}
    online = (now - row["last_heartbeat"]) < ONLINE_WINDOW
    return {
        "linked": True,
        "macId": row["mac_id"],
        "macName": row["mac_name"],
        "macOnline": online,
        "linkedAt": row["linked_at"],
        "lastSeen": row["last_heartbeat"],
    }
