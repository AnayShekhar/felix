"""Per-user Google OAuth token store + consent flow for the Google-API tools.

The Google REST APIs (Docs, Sheets, Gmail, Calendar, Tasks, People, Drive) need
OAuth 2.0 credentials with a refresh token — not the browser cookies the Chrome
extension syncs. This module is where those credentials live, keyed by Lumis
user_id, where the authorization-code consent flow that populates them is
implemented (build_consent_url / exchange_code, driven by the
/connect/google/* routes), and where a googleapiclient is built from them.

Cookie sync signs the *cloud browser* in; THIS flow is what makes
`has_google()` true and unlocks the google_api tool family.

Config (Railway env vars):
  GOOGLE_OAUTH_CLIENT_ID       — Web-application OAuth client
  GOOGLE_OAUTH_CLIENT_SECRET
  PUBLIC_BASE_URL (optional)   — e.g. https://lumis-production-b878.up.railway.app;
                                 the OAuth client must list
                                 {PUBLIC_BASE_URL}/connect/google/callback as an
                                 authorized redirect URI.
"""
import base64
import hashlib
import hmac
import json
import logging
import os
import sqlite3
import time
from typing import Optional
from urllib.parse import urlencode

import db

logger = logging.getLogger("lumis.google_oauth")

CLIENT_ID = os.getenv("GOOGLE_OAUTH_CLIENT_ID", "")
CLIENT_SECRET = os.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "")
TOKEN_URI = "https://oauth2.googleapis.com/token"
AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"

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


class GoogleOAuthNotConfigured(RuntimeError):
    """Raised when GOOGLE_OAUTH_CLIENT_ID/SECRET are missing."""


# --------------------------------------------------------------------------- #
# Consent flow (authorization code + offline access)
# --------------------------------------------------------------------------- #
# The OAuth `state` is a short-lived signed token carrying the Lumis user_id
# through Google's redirect. It is signed with a key DERIVED from the JWT
# secret (domain-separated), so a state token can never be replayed as a Lumis
# session token or vice versa.
_STATE_TTL_S = 10 * 60
_STATE_KEY = hashlib.sha256(
    os.getenv("LUMIS_JWT_SECRET", "lumis-dev-secret-change-me").encode()
    + b"|google-oauth-state"
).digest()


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _b64url_decode(seg: str) -> bytes:
    return base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4))


def make_state(user_id: str) -> str:
    payload = _b64url(json.dumps(
        {"sub": user_id, "exp": int(time.time()) + _STATE_TTL_S},
        separators=(",", ":")).encode())
    sig = _b64url(hmac.new(_STATE_KEY, payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{sig}"


def verify_state(state: str) -> str:
    """Return the user_id carried by a valid, unexpired state token."""
    try:
        payload_seg, sig_seg = state.rsplit(".", 1)
        expected = hmac.new(_STATE_KEY, payload_seg.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64url_decode(sig_seg)):
            raise ValueError("bad signature")
        payload = json.loads(_b64url_decode(payload_seg))
    except Exception as exc:  # noqa: BLE001
        raise ValueError("Invalid state token") from exc
    if payload.get("exp", 0) < int(time.time()):
        raise ValueError("State token expired — start the connect flow again.")
    return payload["sub"]


def _require_client() -> None:
    if not CLIENT_ID or not CLIENT_SECRET:
        raise GoogleOAuthNotConfigured(
            "Google OAuth is not configured. Set GOOGLE_OAUTH_CLIENT_ID and "
            "GOOGLE_OAUTH_CLIENT_SECRET on the server."
        )


def build_consent_url(user_id: str, redirect_uri: str) -> str:
    """The Google consent screen URL for this user.

    access_type=offline + prompt=consent guarantees Google returns a refresh
    token (the thing has_google() requires) even on re-connects.
    """
    _require_client()
    return AUTH_URI + "?" + urlencode({
        "client_id": CLIENT_ID,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(GOOGLE_SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
        "state": make_state(user_id),
    })


def exchange_code(code: str, redirect_uri: str) -> dict:
    """Exchange an authorization code for tokens and return the dict that
    save_tokens() persists. Raises RuntimeError with Google's error on failure.
    """
    _require_client()
    import requests

    resp = requests.post(TOKEN_URI, data={
        "code": code,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }, timeout=30)
    body = resp.json() if resp.content else {}
    if resp.status_code != 200 or "access_token" not in body:
        raise RuntimeError(
            f"Google token exchange failed: "
            f"{body.get('error_description') or body.get('error') or resp.status_code}"
        )
    if not body.get("refresh_token"):
        raise RuntimeError(
            "Google didn't return a refresh token. Remove Lumis from "
            "https://myaccount.google.com/permissions and connect again."
        )
    return {
        "access_token": body["access_token"],
        "refresh_token": body["refresh_token"],
        "token_uri": TOKEN_URI,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scopes": (body.get("scope") or " ".join(GOOGLE_SCOPES)).split(),
    }


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


def delete_user_tokens(user_id: str) -> None:
    """Remove stored Google OAuth tokens for account deletion."""
    with _connect() as conn:
        conn.execute("DELETE FROM google_tokens WHERE user_id = ?", (user_id,))
        conn.commit()


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
