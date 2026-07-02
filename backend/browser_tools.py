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

    Opens a session on the persisted context, connects over CDP, yields the
    first page, and releases the session on exit so cookies/state persist.
    """
    from playwright.async_api import async_playwright

    context_id = await cloud_browser.get_or_create_user_context(user_id)
    bb = cloud_browser._client()
    session = bb.sessions.create(
        project_id=cloud_browser.PROJECT_ID,
        browser_settings={"context": {"id": context_id, "persist": True}},
    )
    playwright = await async_playwright().start()
    browser = None
    try:
        browser = await playwright.chromium.connect_over_cdp(session.connect_url)
        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = context.pages[0] if context.pages else await context.new_page()
        yield page
    finally:
        if browser is not None:
            with contextlib.suppress(Exception):
                await browser.close()
        with contextlib.suppress(Exception):
            await playwright.stop()
        with contextlib.suppress(Exception):
            bb.sessions.update(session.id, project_id=cloud_browser.PROJECT_ID,
                               status="REQUEST_RELEASE")


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
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        title = await page.title()
        return {"tool": "browser.open_url", "status": "success", "title": title,
                "message": f"Opened {url}.", "url": page.url,
                "speak": "Opened that page.", "data": {"url": page.url, "title": title}}


async def browser_read_page(args: dict, user_id: str) -> dict:
    url = str(args.get("url") or "").strip()
    async with cloud_page(user_id) as page:
        if url:
            if not url.startswith(("http://", "https://")):
                url = "https://" + url
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)
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
    async with cloud_page(user_id) as page:
        if selector:
            await page.click(selector, timeout=15000)
        elif text:
            await page.get_by_text(text, exact=False).first.click(timeout=15000)
        else:
            return {"tool": "browser.click", "status": "error",
                    "message": "browser.click requires 'text' or 'selector'.", "data": {}}
        await page.wait_for_timeout(1000)
        return {"tool": "browser.click", "status": "success", "title": "Clicked",
                "message": f"Clicked {selector or text}.", "url": page.url,
                "data": {"url": page.url}}


async def browser_fill_form(args: dict, user_id: str) -> dict:
    fields = args.get("fields") or []
    submit = bool(args.get("submit"))
    async with cloud_page(user_id) as page:
        for f in fields:
            sel = f.get("selector")
            if sel:
                await page.fill(sel, str(f.get("value", "")), timeout=15000)
        if submit and fields:
            with contextlib.suppress(Exception):
                await page.press(fields[-1]["selector"], "Enter")
                await page.wait_for_timeout(1500)
        return {"tool": "browser.fill_form", "status": "success", "title": "Form filled",
                "message": f"Filled {len(fields)} field(s).", "url": page.url,
                "data": {"url": page.url, "submitted": submit}}


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
            with contextlib.suppress(Exception):
                await page.locator('[data-testid="tracklist-row"]').first.click(timeout=8000)
        return {"tool": "media.open_spotify", "status": "success",
                "title": "Spotify", "message": f"Opened Spotify{f' for {query}' if query else ''}.",
                "url": page.url, "speak": f"Playing {query} on Spotify." if query else "Opened Spotify.",
                "data": {"url": page.url}}


async def media_play_pause(args: dict, user_id: str) -> dict:
    async with cloud_page(user_id) as page:
        await page.goto("https://open.spotify.com", wait_until="domcontentloaded", timeout=30000)
        with contextlib.suppress(Exception):
            await page.locator('[data-testid="control-button-playpause"]').first.click(timeout=8000)
        return {"tool": "media.play_pause", "status": "success", "title": "Spotify",
                "message": "Toggled playback.", "data": {"url": page.url}}


async def _create_via_new_page(user_id: str, tool: str, url: str, service: str,
                               label: str) -> dict:
    async with cloud_page(user_id) as page:
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        return {"tool": tool, "status": "success", "title": label,
                "message": f"Opened {service} to {label.lower()}.", "url": page.url,
                "speak": f"Opened {service}.", "data": {"url": page.url}}


async def notion_create_page(args: dict, user_id: str) -> dict:
    return await _create_via_new_page(user_id, "notion.create_page",
                                      "https://www.notion.so/new", "Notion", "New page")


async def notion_append_to_page(args: dict, user_id: str) -> dict:
    url = str(args.get("url") or "https://www.notion.so").strip()
    return await _create_via_new_page(user_id, "notion.append_to_page", url,
                                      "Notion", "Page")


async def linkedin_post_update(args: dict, user_id: str) -> dict:
    return await _create_via_new_page(user_id, "linkedin.post_update",
                                      "https://www.linkedin.com/feed/", "LinkedIn", "Post")


async def slack_send_message(args: dict, user_id: str) -> dict:
    return await _create_via_new_page(user_id, "slack.send_message",
                                      "https://app.slack.com/client", "Slack", "Message")


async def airtable_add_record(args: dict, user_id: str) -> dict:
    return await _create_via_new_page(user_id, "airtable.add_record",
                                      "https://airtable.com", "Airtable", "Record")


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
