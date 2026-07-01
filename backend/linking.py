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
CODE_LENGTH = 6             # 6-digit numeric confirmation code

_SCHEMA = """
CREATE TABLE IF NOT EXISTS link_codes (
    code        TEXT PRIMARY KEY,
    user_id     TEXT,
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
        # Migrate older DBs that predate account-scoped codes.
        cols = {row["name"] for row in conn.execute("PRAGMA table_info(link_codes)")}
        if "user_id" not in cols:
            conn.execute("ALTER TABLE link_codes ADD COLUMN user_id TEXT")
        conn.commit()
    logger.info("Linking tables ready at %s", db.DB_PATH)


def _gen_code() -> str:
    """A 6-digit numeric code (e.g. '048213')."""
    return "".join(secrets.choice("0123456789") for _ in range(CODE_LENGTH))


def is_paired(user_id: str) -> bool:
    """True if this account has confirmed a pairing with a Mac (via the code).

    This is the authority the agent loop checks before dispatching any tool to
    the Mac agent. A Mac WebSocket being connected is NOT enough — the phone must
    have actually entered the 6-digit code for this account.
    """
    if not user_id:
        return False
    with _connect() as conn:
        row = conn.execute(
            "SELECT 1 FROM pairings WHERE user_id = ?", (user_id,)
        ).fetchone()
    return row is not None


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
# Mac-facing endpoints
# --------------------------------------------------------------------------- #
@router.post("/generate")
async def generate(body: GenerateBody, user: dict = Depends(current_user)):
    """The signed-in Mac requests a fresh 6-digit pairing code (valid 10 min).

    The code is bound to the Mac's account, so it can only be confirmed by a
    phone signed into that same account.
    """
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
            "INSERT OR REPLACE INTO link_codes (code, user_id, mac_id, mac_name, created_at, expires_at, used) "
            "VALUES (?, ?, ?, ?, ?, ?, 0)",
            (code, user["id"], mac_id, body.mac_name, now, now + CODE_TTL),
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
    code = "".join(ch for ch in body.code if ch.isdigit())
    now = time.time()
    with _connect() as conn:
        row = conn.execute("SELECT * FROM link_codes WHERE code = ?", (code,)).fetchone()
        if not row or row["used"] or row["expires_at"] < now:
            raise HTTPException(status_code=400, detail="Invalid or expired code. Try again.")
        # The code must have been generated by the SAME account on the Mac.
        if row["user_id"] and row["user_id"] != user["id"]:
            raise HTTPException(
                status_code=403,
                detail="That code was generated on a different account. Sign in with the same account on both devices.",
            )
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
