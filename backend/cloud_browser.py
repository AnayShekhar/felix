"""Browserbase cloud-browser layer for the Chrome extension cookie-sync flow.

The Chrome extension reads the user's logged-in cookies for a service and POSTs
them to /connect/cookies/sync. This module injects those cookies into the user's
*persistent* Browserbase context so every future cloud-browser session Felix
runs is already signed in — no re-login required.

Config (Railway env vars):
  BROWSERBASE_API_KEY      — Browserbase API key
  BROWSERBASE_PROJECT_ID   — Browserbase project id

The `browserbase` SDK and Playwright are imported lazily so the rest of the
backend still boots if they are not installed / not configured; callers get a
clear error only when a cloud-browser operation is actually attempted.
"""
import asyncio
import logging
import os
import time
from typing import Dict, List, Optional

import connections

logger = logging.getLogger("felix.cloud_browser")

API_KEY = os.getenv("BROWSERBASE_API_KEY", "")
PROJECT_ID = os.getenv("BROWSERBASE_PROJECT_ID", "")

# How long an idle live browser session stays open. Within a single agent run
# (and quick follow-ups) tools share one session so page state survives between
# steps; after this idle window the session is released so the persisted
# context (cookies, logins) is flushed back to Browserbase.
LIVE_IDLE_S = int(os.getenv("BROWSER_SESSION_IDLE_S", "180"))


class CloudBrowserNotConfigured(RuntimeError):
    """Raised when Browserbase credentials or SDKs are unavailable."""


def _client():
    """Return a Browserbase client, or raise CloudBrowserNotConfigured."""
    if not API_KEY or not PROJECT_ID:
        raise CloudBrowserNotConfigured(
            "Cloud browser is not configured. Set BROWSERBASE_API_KEY and "
            "BROWSERBASE_PROJECT_ID."
        )
    try:
        from browserbase import Browserbase
    except ImportError as exc:  # pragma: no cover - depends on deploy env
        raise CloudBrowserNotConfigured(
            "The 'browserbase' package is not installed on the server."
        ) from exc
    return Browserbase(api_key=API_KEY)


async def get_or_create_user_context(user_id: str) -> str:
    """Return the user's persistent Browserbase context id, creating one on first use."""
    existing = connections.get_context_id(user_id)
    if existing:
        return existing

    bb = _client()
    context = bb.contexts.create(project_id=PROJECT_ID)
    context_id = context.id
    connections.set_context_id(user_id, context_id)
    logger.info("Created Browserbase context %s for user %s", context_id, user_id)
    return context_id


def _to_playwright_cookies(cookies: List[dict]) -> List[dict]:
    """Map extension-captured cookies into Playwright's add_cookies() shape."""
    out = []
    for c in cookies:
        # Chrome's cookies API reports "no_restriction" for SameSite=None —
        # mapping that to Lax would break cross-site auth cookies.
        raw = str(c.get("sameSite") or "").lower()
        same = {"lax": "Lax", "strict": "Strict",
                "none": "None", "no_restriction": "None"}.get(raw, "Lax")
        cookie = {
            "name": c["name"],
            "value": c["value"],
            "domain": c["domain"],
            "path": c.get("path", "/"),
            "secure": c.get("secure", True),
            "httpOnly": c.get("httpOnly", False),
            "sameSite": same,
        }
        # Playwright wants a numeric unix-seconds `expires` or -1 for session.
        exp = c.get("expirationDate")
        cookie["expires"] = float(exp) if exp is not None else -1
        out.append(cookie)
    return out


# --------------------------------------------------------------------------- #
# Live per-user browser sessions
#
# One Browserbase session per user is kept open across tool calls, so a
# multi-step flow (open → click → fill) operates on the SAME page instead of
# each step getting a fresh session at about:blank. Browserbase allows a single
# active session per context, so everything that opens a session on the user's
# context (tools, cookie sync, verify) must go through / around this registry.
# --------------------------------------------------------------------------- #
_live: Dict[str, dict] = {}          # user_id -> {playwright, browser, page, session_id, last_used}
_user_locks: Dict[str, asyncio.Lock] = {}


def user_lock(user_id: str) -> asyncio.Lock:
    """The per-user lock serializing access to that user's live session."""
    return _user_locks.setdefault(user_id, asyncio.Lock())


async def _open_live(user_id: str) -> dict:
    from playwright.async_api import async_playwright

    context_id = await get_or_create_user_context(user_id)
    bb = _client()
    session = bb.sessions.create(
        project_id=PROJECT_ID,
        browser_settings={"context": {"id": context_id, "persist": True}},
    )
    playwright = await async_playwright().start()
    try:
        browser = await playwright.chromium.connect_over_cdp(session.connect_url)
        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = context.pages[0] if context.pages else await context.new_page()
    except Exception:
        with _suppress():
            await playwright.stop()
        with _suppress():
            bb.sessions.update(session.id, project_id=PROJECT_ID,
                               status="REQUEST_RELEASE")
        raise
    logger.info("Opened live browser session %s for user %s", session.id, user_id)
    return {"playwright": playwright, "browser": browser, "page": page,
            "session_id": session.id, "last_used": time.time()}


def _suppress():
    import contextlib
    return contextlib.suppress(Exception)


async def _close_record(user_id: str, rec: dict) -> None:
    _live.pop(user_id, None)
    with _suppress():
        await rec["browser"].close()
    with _suppress():
        await rec["playwright"].stop()
    with _suppress():
        _client().sessions.update(rec["session_id"], project_id=PROJECT_ID,
                                  status="REQUEST_RELEASE")
    logger.info("Released live browser session %s for user %s",
                rec.get("session_id"), user_id)


async def acquire_live_page(user_id: str):
    """Return the user's live page, opening a session if needed.

    Caller MUST hold `user_lock(user_id)`.
    """
    rec = _live.get(user_id)
    if rec is not None:
        page = rec["page"]
        alive = False
        try:
            alive = rec["browser"].is_connected() and not page.is_closed()
        except Exception:  # noqa: BLE001
            alive = False
        if alive:
            rec["last_used"] = time.time()
            return page
        await _close_record(user_id, rec)
    rec = await _open_live(user_id)
    _live[user_id] = rec
    return rec["page"]


async def discard_live_session_locked(user_id: str) -> None:
    """Close the user's live session. Caller MUST hold `user_lock(user_id)`."""
    rec = _live.get(user_id)
    if rec is not None:
        await _close_record(user_id, rec)


async def release_live_session(user_id: str) -> None:
    """Close the user's live session (if any), flushing the persisted context.

    Safe to call from anywhere (acquires the user's lock). Called when an agent
    run finishes and before cookie sync (one active session per context).
    """
    async with user_lock(user_id):
        await discard_live_session_locked(user_id)


async def reap_idle_sessions() -> None:
    """Opportunistically close sessions idle past LIVE_IDLE_S."""
    now = time.time()
    for uid in list(_live.keys()):
        rec = _live.get(uid)
        if rec is None or now - rec["last_used"] <= LIVE_IDLE_S:
            continue
        lock = user_lock(uid)
        if lock.locked():
            continue  # in use — not actually idle
        async with lock:
            rec = _live.get(uid)
            if rec is not None and time.time() - rec["last_used"] > LIVE_IDLE_S:
                await _close_record(uid, rec)


async def inject_cookies_into_context(context_id: str, cookies: List[dict]) -> None:
    """Open a short-lived session on the persistent context, add cookies, release.

    The cookies persist with the context (persist=True) for all future sessions.
    """
    from playwright.async_api import async_playwright

    bb = _client()
    session = bb.sessions.create(
        project_id=PROJECT_ID,
        browser_settings={"context": {"id": context_id, "persist": True}},
    )

    playwright = await async_playwright().start()
    try:
        browser = await playwright.chromium.connect_over_cdp(session.connect_url)
        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        await context.add_cookies(_to_playwright_cookies(cookies))
        await browser.close()
    finally:
        await playwright.stop()
        # Release the session so the persisted context is flushed and reusable.
        try:
            bb.sessions.update(session.id, project_id=PROJECT_ID, status="REQUEST_RELEASE")
        except Exception as exc:  # noqa: BLE001 - best-effort release
            logger.warning("Failed to release Browserbase session %s: %s", session.id, exc)
