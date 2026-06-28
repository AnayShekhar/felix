"""Authentication for Lumis: email/password + Sign in with Apple + Google.

Standard-library + already-installed deps only (no new pip packages):
- Our own session tokens are HS256 JWTs signed with `hmac`/`hashlib`.
- Passwords are hashed with PBKDF2-HMAC-SHA256 (`hashlib.pbkdf2_hmac`).
- Google ID tokens are verified with the installed `google-auth`.
- Apple identity tokens are verified with `cryptography` against Apple's JWKS.

Users live in the same SQLite file as the action history (see db.py).
"""
import base64
import hashlib
import hmac
import json
import logging
import os
import sqlite3
import time
import uuid
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel

import db

logger = logging.getLogger("lumis.auth")

# Signing secret for our session JWTs. Set LUMIS_JWT_SECRET in the Railway env
# for production; the default keeps local dev working out of the box.
_JWT_SECRET = os.getenv("LUMIS_JWT_SECRET", "lumis-dev-secret-change-me").encode()
_TOKEN_TTL = 60 * 60 * 24 * 30  # 30 days
_GOOGLE_CLIENT_ID = os.getenv("LUMIS_GOOGLE_CLIENT_ID")  # optional audience check
_APPLE_BUNDLE_ID = os.getenv("LUMIS_APPLE_BUNDLE_ID", "com.anay.lumis")

router = APIRouter(prefix="/auth", tags=["auth"])


# --------------------------------------------------------------------------- #
# Schema
# --------------------------------------------------------------------------- #
_USER_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    email         TEXT UNIQUE NOT NULL,
    name          TEXT,
    password_hash TEXT,
    provider      TEXT NOT NULL DEFAULT 'email',
    created_at    REAL NOT NULL
);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_auth() -> None:
    """Create the users table. Safe to call repeatedly."""
    with _connect() as conn:
        conn.executescript(_USER_SCHEMA)
    logger.info("Users table ready at %s", db.DB_PATH)


# --------------------------------------------------------------------------- #
# Password hashing (PBKDF2)
# --------------------------------------------------------------------------- #
_PBKDF2_ROUNDS = 200_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ROUNDS)
    return f"pbkdf2_sha256${_PBKDF2_ROUNDS}${salt.hex()}${dk.hex()}"


def verify_password(password: str, stored: Optional[str]) -> bool:
    if not stored:
        return False
    try:
        _, rounds, salt_hex, hash_hex = stored.split("$")
        dk = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt_hex), int(rounds)
        )
        return hmac.compare_digest(dk.hex(), hash_hex)
    except (ValueError, TypeError):
        return False


# --------------------------------------------------------------------------- #
# JWT (HS256)
# --------------------------------------------------------------------------- #
def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _b64url_decode(seg: str) -> bytes:
    return base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4))


def issue_token(user_id: str, email: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {"sub": user_id, "email": email, "iat": now, "exp": now + _TOKEN_TTL}
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    sig = hmac.new(_JWT_SECRET, signing_input.encode(), hashlib.sha256).digest()
    return signing_input + "." + _b64url(sig)


def verify_token(token: str) -> dict:
    try:
        signing_input, sig_seg = token.rsplit(".", 1)
        expected = hmac.new(_JWT_SECRET, signing_input.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64url_decode(sig_seg)):
            raise ValueError("bad signature")
        payload = json.loads(_b64url_decode(signing_input.split(".", 1)[1]))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=401, detail="Invalid token") from exc
    if payload.get("exp", 0) < int(time.time()):
        raise HTTPException(status_code=401, detail="Token expired")
    return payload


# --------------------------------------------------------------------------- #
# User store
# --------------------------------------------------------------------------- #
def _row_to_user(row: sqlite3.Row) -> dict:
    return {"id": row["id"], "email": row["email"], "name": row["name"], "provider": row["provider"]}


def get_user_by_email(email: str) -> Optional[sqlite3.Row]:
    with _connect() as conn:
        return conn.execute(
            "SELECT * FROM users WHERE email = ?", (email.lower(),)
        ).fetchone()


def get_user_by_id(user_id: str) -> Optional[sqlite3.Row]:
    with _connect() as conn:
        return conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def create_user(email: str, name: str, password: Optional[str], provider: str = "email") -> dict:
    user_id = str(uuid.uuid4())
    with _connect() as conn:
        conn.execute(
            "INSERT INTO users (id, email, name, password_hash, provider, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                user_id,
                email.lower(),
                name,
                hash_password(password) if password else None,
                provider,
                time.time(),
            ),
        )
        conn.commit()
    return {"id": user_id, "email": email.lower(), "name": name, "provider": provider}


def _upsert_oauth_user(email: str, name: str, provider: str) -> dict:
    existing = get_user_by_email(email)
    if existing:
        return _row_to_user(existing)
    return create_user(email, name, None, provider)


# --------------------------------------------------------------------------- #
# OAuth token verification
# --------------------------------------------------------------------------- #
def _verify_google(id_token_str: str) -> dict:
    from google.auth.transport import requests as g_requests
    from google.oauth2 import id_token as g_id_token

    info = g_id_token.verify_oauth2_token(
        id_token_str, g_requests.Request(), audience=_GOOGLE_CLIENT_ID
    )
    email = info.get("email")
    if not email:
        raise HTTPException(status_code=401, detail="Google token has no email")
    name = info.get("name") or email.split("@")[0]
    return _upsert_oauth_user(email, name, "google")


def _verify_apple(identity_token: str, full_name: Optional[str]) -> dict:
    from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers

    def _int(seg: str) -> int:
        return int.from_bytes(_b64url_decode(seg), "big")

    try:
        header = json.loads(_b64url_decode(identity_token.split(".")[0]))
        kid = header["kid"]
        jwks = httpx.get("https://appleid.apple.com/auth/keys", timeout=10).json()["keys"]
        jwk = next(k for k in jwks if k["kid"] == kid)
        pub = RSAPublicNumbers(e=_int(jwk["e"]), n=_int(jwk["n"])).public_key()

        signing_input, sig_seg = identity_token.rsplit(".", 1)
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding

        pub.verify(
            _b64url_decode(sig_seg),
            signing_input.encode(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        claims = json.loads(_b64url_decode(identity_token.split(".")[1]))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=401, detail="Invalid Apple token") from exc

    if claims.get("iss") != "https://appleid.apple.com":
        raise HTTPException(status_code=401, detail="Bad Apple issuer")
    if claims.get("exp", 0) < int(time.time()):
        raise HTTPException(status_code=401, detail="Apple token expired")
    email = claims.get("email")
    if not email:
        raise HTTPException(status_code=401, detail="Apple token has no email")
    name = full_name or email.split("@")[0]
    return _upsert_oauth_user(email, name, "apple")


# --------------------------------------------------------------------------- #
# FastAPI dependency
# --------------------------------------------------------------------------- #
def current_user(authorization: str = Header(None)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    payload = verify_token(authorization.split(" ", 1)[1].strip())
    row = get_user_by_id(payload["sub"])
    if not row:
        raise HTTPException(status_code=401, detail="User not found")
    return _row_to_user(row)


# --------------------------------------------------------------------------- #
# Request models
# --------------------------------------------------------------------------- #
class RegisterBody(BaseModel):
    email: str
    password: str
    name: str = ""


class LoginBody(BaseModel):
    email: str
    password: str


class AppleBody(BaseModel):
    identityToken: str
    fullName: str = ""


class GoogleBody(BaseModel):
    idToken: str


# --------------------------------------------------------------------------- #
# Endpoints
# --------------------------------------------------------------------------- #
@router.post("/register")
async def register(body: RegisterBody):
    email = body.email.strip().lower()
    if "@" not in email or len(body.password) < 6:
        raise HTTPException(status_code=400, detail="Invalid email or password too short")
    if get_user_by_email(email):
        raise HTTPException(status_code=409, detail="An account with that email already exists")
    user = create_user(email, body.name.strip() or email.split("@")[0], body.password)
    return {"token": issue_token(user["id"], user["email"]), "user": user}


@router.post("/login")
async def login(body: LoginBody):
    row = get_user_by_email(body.email.strip().lower())
    if not row or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    user = _row_to_user(row)
    return {"token": issue_token(user["id"], user["email"]), "user": user}


@router.post("/apple")
async def apple(body: AppleBody):
    user = _verify_apple(body.identityToken, body.fullName or None)
    return {"token": issue_token(user["id"], user["email"]), "user": user}


@router.post("/google")
async def google(body: GoogleBody):
    user = _verify_google(body.idToken)
    return {"token": issue_token(user["id"], user["email"]), "user": user}


@router.post("/logout")
async def logout(user: dict = Depends(current_user)):
    # Stateless JWTs: logout is client-side (drop the token). Endpoint exists so
    # the client can confirm the token was valid and for future token revocation.
    return {"success": True}


@router.delete("/account")
async def delete_account(user: dict = Depends(current_user)):
    with _connect() as conn:
        conn.execute("DELETE FROM users WHERE id = ?", (user["id"],))
        conn.commit()
    return {"success": True}


@router.get("/me")
async def me(user: dict = Depends(current_user)):
    return {"user": user}
