"""Cloud-browser tool implementations, running on the user's persistent
Browserbase context (so the cookies synced from the Chrome extension are already
signed in). Replaces the local-Playwright browser tools that ran on the Mac.

Each tool is async and takes (args, user_id), returning the standard Lumis
contract. web.* tools have no browser/auth dependency and are delegated to
tools.py so they keep working even when Browserbase isn't configured.
"""
import contextlib
import logging
from typing import Optional

import cloud_browser
from cloud_browser import CloudBrowserNotConfigured

logger = logging.getLogger("lumis.browser_tools")


@contextlib.asynccontextmanager
async def cloud_page(user_id: str):
    """Yield a Playwright page bound to the user's persistent Browserbase context.

    Reuses the user's LIVE session (cloud_browser keeps one open per user), so
    consecutive tool calls in an agent run see the same page — open → click →
    fill actually operate on the page the previous step left, instead of each
    step starting over at about:blank. The session is released when the agent
    run finishes (release_session) or after an idle timeout, which is when the
    persisted context (cookies/logins) is flushed back to Browserbase.
    """
    async with cloud_browser.user_lock(user_id):
        await cloud_browser.reap_idle_sessions()
        page = await cloud_browser.acquire_live_page(user_id)
        try:
            yield page
        except Exception:
            # A broken page/session must not poison the next call — discard it.
            await cloud_browser.discard_live_session_locked(user_id)
            raise


async def release_session(user_id: str) -> None:
    """Flush + close the user's live browser session; never raises."""
    try:
        await cloud_browser.release_live_session(user_id)
    except Exception:  # noqa: BLE001 - cleanup is best-effort
        logger.warning("release_session failed for %s", user_id, exc_info=True)


# --------------------------------------------------------------------------- #
# General-purpose reliability helpers
#
# Every interactive browser tool goes through these so behaviour is consistent
# on ANY site under real network conditions — not just the happy path. They wait
# for the page/element to be genuinely ready, try several locator strategies, and
# never raise (callers decide what a failure means).
# --------------------------------------------------------------------------- #
async def reliable_goto(page, url: str, timeout: int = 20000) -> None:
    """Navigate and wait for the page to be meaningfully interactive, not just loaded."""
    await page.goto(url, wait_until="domcontentloaded", timeout=timeout)
    with contextlib.suppress(Exception):
        # Some sites (YouTube, infinite-scroll pages) never go fully idle — fine.
        await page.wait_for_load_state("networkidle", timeout=5000)
    await page.wait_for_timeout(500)  # let any final JS-driven layout settle


async def reliable_click(page, selector: Optional[str] = None,
                         text: Optional[str] = None, timeout: int = 10000) -> bool:
    """Click via fallback strategies (CSS → text → role → label); never raises.

    Returns True if a click succeeded, False otherwise.
    """
    strategies = []
    if selector:
        strategies.append(lambda: page.locator(selector).first)
    if text:
        strategies.append(lambda: page.get_by_text(text, exact=False).first)
        strategies.append(lambda: page.get_by_role("button", name=text).first)
        strategies.append(lambda: page.get_by_role("link", name=text).first)
        strategies.append(lambda: page.get_by_label(text).first)
    if not strategies:
        return False

    per_try = max(1500, int(timeout / len(strategies)))
    for build_locator in strategies:
        try:
            locator = build_locator()
            await locator.wait_for(state="visible", timeout=per_try)
            await locator.scroll_into_view_if_needed()
            await locator.click(timeout=3000)
            return True
        except Exception:
            continue
    return False


async def reliable_fill(page, selector_or_label: str, value: str,
                        timeout: int = 5000) -> bool:
    """Fill a field trying selector → placeholder → label → name attribute; never raises."""
    if not selector_or_label:
        return False
    attempts = [
        lambda: page.locator(selector_or_label).first,
        lambda: page.get_by_placeholder(selector_or_label).first,
        lambda: page.get_by_label(selector_or_label).first,
        lambda: page.locator(f'[name="{selector_or_label}"]').first,
    ]
    for build_locator in attempts:
        try:
            locator = build_locator()
            await locator.wait_for(state="visible", timeout=timeout)
            await locator.fill(str(value), timeout=timeout)
            return True
        except Exception:
            continue
    return False


async def verify_with_screenshot(page) -> Optional[str]:
    """Base64 PNG of the current page so the agent can visually confirm the result.

    agent.py feeds any `image_b64` in a tool result back into the loop as a vision
    message, so the model can catch a click that "succeeded" but did the wrong thing.
    """
    import base64
    try:
        png = await page.screenshot(type="png")
        return base64.b64encode(png).decode()
    except Exception:  # noqa: BLE001 - a missing screenshot must never fail the tool
        return None


# --------------------------------------------------------------------------- #
# Generic browser tools
# --------------------------------------------------------------------------- #
async def browser_open_url(args: dict, user_id: str) -> dict:
    url = str(args.get("url") or "").strip()
    if not url:
        return {"tool": "browser.open_url", "status": "error",
                "message": "browser.open_url requires a 'url'.", "data": {}}
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    async with cloud_page(user_id) as page:
        await reliable_goto(page, url)
        title = await page.title()
        return {"tool": "browser.open_url", "status": "success", "title": title,
                "message": f"Opened {title or url}.", "url": page.url,
                "speak": "Opened that page.", "data": {"url": page.url, "title": title}}


async def browser_read_page(args: dict, user_id: str) -> dict:
    url = str(args.get("url") or "").strip()
    async with cloud_page(user_id) as page:
        if url:
            if not url.startswith(("http://", "https://")):
                url = "https://" + url
            await reliable_goto(page, url)
        text = (await page.inner_text("body"))[:3000]
        links = await page.eval_on_selector_all(
            "a[href]",
            "els => els.slice(0,40).map(e => ({text: e.innerText.trim(), href: e.href}))",
        )
        links = [l for l in links if l.get("text")][:25]
        listing = "\n".join(f"[{i}] {l['text']} -> {l['href']}"
                            for i, l in enumerate(links))
        return {"tool": "browser.read_page", "status": "success",
                "title": await page.title(), "message": "Read the page.",
                "summary": text[:800], "url": page.url,
                "data": {"text": text, "links": links, "link_list": listing}}


async def browser_click(args: dict, user_id: str) -> dict:
    text = str(args.get("text") or "").strip()
    selector = str(args.get("selector") or "").strip()
    if not text and not selector:
        return {"tool": "browser.click", "status": "error",
                "message": "browser.click requires 'text' or 'selector'.", "data": {}}
    async with cloud_page(user_id) as page:
        success = await reliable_click(page, selector=selector or None, text=text or None)
        if not success:
            return {"tool": "browser.click", "status": "error",
                    "message": f"Couldn't find or click {selector or repr(text)}.",
                    "url": page.url,
                    "image_b64": await verify_with_screenshot(page),
                    "data": {"url": page.url}}
        await page.wait_for_timeout(800)  # let the click's effect (nav/popup) settle
        return {"tool": "browser.click", "status": "success", "title": "Clicked",
                "message": f"Clicked {selector or text}.", "url": page.url,
                "image_b64": await verify_with_screenshot(page),
                "data": {"url": page.url}}


def _field_key(f: dict) -> str:
    """Locator hint for a form field — selector wins, else label/name/placeholder."""
    return str(f.get("selector") or f.get("label") or f.get("name")
               or f.get("placeholder") or "").strip()


async def browser_fill_form(args: dict, user_id: str) -> dict:
    raw = args.get("fields") or []
    # Accept both a list of {selector/label, value} and a plain {key: value} dict.
    if isinstance(raw, dict):
        fields = [{"selector": k, "value": v} for k, v in raw.items()]
    else:
        fields = list(raw)
    submit = bool(args.get("submit"))
    async with cloud_page(user_id) as page:
        filled, failed = [], []
        for f in fields:
            key = _field_key(f)
            ok = await reliable_fill(page, key, f.get("value", ""))
            (filled if ok else failed).append(key or "(unnamed)")
        if submit and filled:
            with contextlib.suppress(Exception):
                await page.keyboard.press("Enter")
                await page.wait_for_timeout(800)
        return {
            "tool": "browser.fill_form",
            "status": "success" if filled else "error",
            "title": "Form filled" if filled else "Couldn't fill form",
            "message": (f"Filled: {', '.join(filled) or 'none'}. "
                        f"Failed: {', '.join(failed) or 'none'}."),
            "url": page.url,
            "speak": "Done." if filled else "I couldn't find those fields on this page.",
            "image_b64": await verify_with_screenshot(page),
            "data": {"url": page.url, "submitted": submit,
                     "filled": filled, "failed": failed},
        }


async def browser_screenshot(args: dict, user_id: str) -> dict:
    import base64
    async with cloud_page(user_id) as page:
        png = await page.screenshot(type="png")
        b64 = base64.b64encode(png).decode()
        return {"tool": "browser.screenshot", "status": "success", "title": "Screenshot",
                "message": "Captured the browser.", "url": page.url,
                "image_b64": b64, "data": {"url": page.url}}


# --------------------------------------------------------------------------- #
# Service-specific (need the matching cookies synced via the extension)
# --------------------------------------------------------------------------- #
async def media_open_spotify(args: dict, user_id: str) -> dict:
    query = str(args.get("query") or args.get("search_query") or "").strip()
    async with cloud_page(user_id) as page:
        target = (f"https://open.spotify.com/search/{query}"
                  if query else "https://open.spotify.com")
        await page.goto(target, wait_until="domcontentloaded", timeout=30000)
        await page.wait_for_timeout(1500)
        if query:
            try:
                await page.locator('[data-testid="tracklist-row"]').first.click(timeout=8000)
            except Exception as exc:  # noqa: BLE001
                return {"tool": "media.open_spotify", "status": "error",
                        "title": "Spotify",
                        "message": f"Opened Spotify search for {query} but couldn't start playback: {exc}",
                        "url": page.url, "speak": f"Couldn't play {query} on Spotify.",
                        "data": {"url": page.url, "query": query}}
        return {"tool": "media.open_spotify", "status": "success",
                "title": "Spotify", "message": f"Opened Spotify{f' for {query}' if query else ''}.",
                "url": page.url, "speak": f"Playing {query} on Spotify." if query else "Opened Spotify.",
                "data": {"url": page.url}}


async def media_play_pause(args: dict, user_id: str) -> dict:
    async with cloud_page(user_id) as page:
        await page.goto("https://open.spotify.com", wait_until="domcontentloaded", timeout=30000)
        try:
            await page.locator('[data-testid="control-button-playpause"]').first.click(timeout=8000)
        except Exception as exc:  # noqa: BLE001
            return {"tool": "media.play_pause", "status": "error", "title": "Spotify",
                    "message": f"Couldn't toggle playback: {exc}", "url": page.url,
                    "speak": "Couldn't control Spotify playback.",
                    "data": {"url": page.url}}
        return {"tool": "media.play_pause", "status": "success", "title": "Spotify",
                "message": "Toggled playback.", "url": page.url,
                "data": {"url": page.url}}


async def _open_service_page(user_id: str, tool: str, url: str, service: str,
                             intent: str, content_hint: str = "") -> dict:
    """Open a service page for the user to finish — do NOT pretend the action completed.

    These tools drive a cloud browser signed in via synced cookies. Full
    create/post/send automation is incomplete; we open the right surface and
    return an honest `opened` status so the agent/UI don't claim success.
    """
    async with cloud_page(user_id) as page:
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        hint = f" Suggested content: {content_hint}" if content_hint else ""
        return {
            "tool": tool,
            "status": "success",
            "title": f"{service} opened",
            "message": (
                f"Opened {service} for you to {intent} yourself in the cloud browser."
                f"{hint} Lumis cannot fully automate this action yet."
            ),
            "url": page.url,
            "speak": f"Opened {service}. Finish {intent} there.",
            "data": {"url": page.url, "automated": False, "intent": intent},
        }


async def notion_create_page(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or args.get("name") or "").strip()
    return await _open_service_page(
        user_id, "notion.create_page", "https://www.notion.so/new", "Notion",
        "create the page", title)


async def notion_append_to_page(args: dict, user_id: str) -> dict:
    url = str(args.get("url") or "https://www.notion.so").strip()
    text = str(args.get("text") or args.get("content") or "").strip()
    return await _open_service_page(
        user_id, "notion.append_to_page", url, "Notion",
        "append the content", text[:200])


async def linkedin_post_update(args: dict, user_id: str) -> dict:
    text = str(args.get("text") or args.get("content") or "").strip()
    return await _open_service_page(
        user_id, "linkedin.post_update", "https://www.linkedin.com/feed/",
        "LinkedIn", "post the update", text[:200])


async def slack_send_message(args: dict, user_id: str) -> dict:
    text = str(args.get("text") or args.get("message") or "").strip()
    return await _open_service_page(
        user_id, "slack.send_message", "https://app.slack.com/client",
        "Slack", "send the message", text[:200])


async def airtable_add_record(args: dict, user_id: str) -> dict:
    return await _open_service_page(
        user_id, "airtable.add_record", "https://airtable.com",
        "Airtable", "add the record")


_BROWSER_TOOLS = {
    "browser.open_url": browser_open_url,
    "browser.read_page": browser_read_page,
    "browser.click": browser_click,
    "browser.fill_form": browser_fill_form,
    "browser.screenshot": browser_screenshot,
    "media.open_spotify": media_open_spotify,
    "media.play_pause": media_play_pause,
    "notion.create_page": notion_create_page,
    "notion.append_to_page": notion_append_to_page,
    "linkedin.post_update": linkedin_post_update,
    "slack.send_message": slack_send_message,
    "airtable.add_record": airtable_add_record,
}

# web.* run cloud-side with no browser/auth — delegated to tools.py.
_WEB_TOOLS = {"web.search", "web.fetch_page", "web.research"}


async def execute_browser_tool(tool: str, args: dict, user_id: str) -> dict:
    """Run a cloud-browser or web tool. Never raises — always a contract."""
    if tool in _WEB_TOOLS:
        import asyncio
        import tools
        return await asyncio.get_event_loop().run_in_executor(
            None, tools.execute_cloud_tool, tool, args, user_id)

    fn = _BROWSER_TOOLS.get(tool)
    if fn is None:
        return {"tool": tool, "status": "error",
                "message": f"Unknown browser tool: {tool}", "data": {}}
    try:
        return await fn(args or {}, user_id)
    except CloudBrowserNotConfigured as exc:
        return {"tool": tool, "status": "error", "message": str(exc),
                "title": "Browser unavailable",
                "speak": "The cloud browser isn't set up yet.",
                "data": {"error": "cloud_browser_not_configured"}}
    except Exception as exc:  # noqa: BLE001
        logger.exception("Browser tool %s failed", tool)
        return {"tool": tool, "status": "error", "message": f"{tool} failed: {exc}",
                "speak": "That didn't work in the browser.", "data": {"error": str(exc)}}
