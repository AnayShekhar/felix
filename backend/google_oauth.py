"""Per-user Google OAuth token store for the Google-API tool layer.

The Google REST APIs (Docs, Sheets, Gmail, Calendar, Tasks, People, Drive) need
OAuth 2.0 credentials with a refresh token — not the browser cookies the Chrome
extension syncs. This module is where those credentials live, keyed by Lumis
user_id, and where a googleapiclient is built from them.

IMPORTANT — connection gap: the current account-connection mechanism
(chrome-extension → /connect/cookies/sync) captures *cookies*, which cannot be
exchanged for API tokens. Until a proper Google OAuth consent flow is added
(authorization-code + offline access, populating this store via save_tokens),
`has_google()` returns False and every Google-API tool returns a clean
"Google isn't connected for API access yet" error rather than crashing.

Config (Railway env vars), required only to refresh tokens:
  GOOGLE_OAUTH_CLIENT_ID
  GOOGLE_OAUTH_CLIENT_SECRET
"""
import json
import logging
import os
import sqlite3
import time
from typing import Optional

import db

logger = logging.getLogger("lumis.google_oauth")

CLIENT_ID = os.getenv("GOOGLE_OAUTH_CLIENT_ID", "")
CLIENT_SECRET = os.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "")
TOKEN_URI = "https://oauth2.googleapis.com/token"

# All scopes the tool layer may use. A real consent flow must request these.
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/contacts.readonly",
    "https://www.googleapis.com/auth/drive",
]

_SCHEMA = """
CREATE TABLE IF NOT EXISTS google_tokens (
    user_id       TEXT PRIMARY KEY,
    token_json    TEXT NOT NULL,
    updated_at    REAL NOT NULL
);
"""


class GoogleNotConnected(RuntimeError):
    """Raised when a user has no usable Google API credentials."""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_google_oauth() -> None:
    with _connect() as conn:
        conn.executescript(_SCHEMA)
    logger.info("Google token table ready at %s", db.DB_PATH)


def save_tokens(user_id: str, token: dict) -> None:
    """Persist an OAuth token dict (access_token, refresh_token, scopes, ...)."""
    with _connect() as conn:
        conn.execute(
            "INSERT INTO google_tokens (user_id, token_json, updated_at) "
            "VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET "
            "token_json = excluded.token_json, updated_at = excluded.updated_at",
            (user_id, json.dumps(token), time.time()),
        )
        conn.commit()


def _load_token(user_id: str) -> Optional[dict]:
    with _connect() as conn:
        row = conn.execute(
            "SELECT token_json FROM google_tokens WHERE user_id = ?", (user_id,)
        ).fetchone()
    if not row:
        return None
    try:
        return json.loads(row["token_json"])
    except (ValueError, TypeError):
        return None


def has_google(user_id: str) -> bool:
    """True if this user has stored Google credentials with a refresh token."""
    tok = _load_token(user_id)
    return bool(tok and tok.get("refresh_token"))


def get_credentials(user_id: str):
    """Build a refreshable google.oauth2 Credentials object for the user.

    Raises GoogleNotConnected if no credentials are stored or the google-auth
    library is unavailable.
    """
    tok = _load_token(user_id)
    if not tok or not tok.get("refresh_token"):
        raise GoogleNotConnected(
            "Google isn't connected for API access yet. Connect Google to Lumis "
            "to enable Docs, Sheets, Gmail, Calendar, Tasks and Drive."
        )
    try:
        from google.oauth2.credentials import Credentials
    except ImportError as exc:  # pragma: no cover
        raise GoogleNotConnected("google-auth is not installed on the server.") from exc

    creds = Credentials(
        token=tok.get("access_token"),
        refresh_token=tok.get("refresh_token"),
        token_uri=tok.get("token_uri", TOKEN_URI),
        client_id=tok.get("client_id") or CLIENT_ID,
        client_secret=tok.get("client_secret") or CLIENT_SECRET,
        scopes=tok.get("scopes") or GOOGLE_SCOPES,
    )
    # Refresh + persist the rotated access token if expired.
    try:
        if not creds.valid:
            from google.auth.transport.requests import Request

            creds.refresh(Request())
            tok["access_token"] = creds.token
            save_tokens(user_id, tok)
    except Exception as exc:  # noqa: BLE001
        raise GoogleNotConnected(f"Google session expired, reconnect needed: {exc}")
    return creds
