"""Browserbase cloud-browser layer for the Chrome extension cookie-sync flow.

The Chrome extension reads the user's logged-in cookies for a service and POSTs
them to /connect/cookies/sync. This module injects those cookies into the user's
*persistent* Browserbase context so every future cloud-browser session Lumis
runs is already signed in — no re-login required.

Config (Railway env vars):
  BROWSERBASE_API_KEY      — Browserbase API key
  BROWSERBASE_PROJECT_ID   — Browserbase project id

The `browserbase` SDK and Playwright are imported lazily so the rest of the
backend still boots if they are not installed / not configured; callers get a
clear error only when a cloud-browser operation is actually attempted.
"""
import logging
import os
from typing import List

import connections

logger = logging.getLogger("lumis.cloud_browser")

API_KEY = os.getenv("BROWSERBASE_API_KEY", "")
PROJECT_ID = os.getenv("BROWSERBASE_PROJECT_ID", "")


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
        same = c.get("sameSite")
        same = (
            same.capitalize()
            if isinstance(same, str) and same.lower() in ("lax", "strict", "none")
            else "Lax"
        )
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
