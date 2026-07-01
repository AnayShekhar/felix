"""Lumis Mac agent — the local "hands" of the split architecture.

The Lumis backend runs on Railway (Linux), which cannot run osascript, pmset,
screencapture, or touch the local filesystem. This agent runs on your Mac,
connects to the Railway backend over the same /ws WebSocket as a special "mac"
client, and executes those macOS-local tools locally on your behalf:

    Railway  = brain (cloud, always on, plans via Groq)
    mac_agent = hands (local, runs osascript/shell tools here)
    iOS app  = eyes and ears (mobile input)

Protocol
--------
On connect it sends            {"event": "register", "role": "mac"}.
The backend pushes             {"event": "execute_on_mac",
                                "data": {"action_id", "tool", "args"}}.
The agent runs the tool via tools.execute() and replies
                               {"event": "mac_result",
                                "data": {"action_id", "result"}}.

Run it with ../run_mac_agent.sh, or directly: ./venv/bin/python mac_agent.py
The backend URL comes from $LUMIS_BACKEND_URL (defaults to the Railway URL);
http(s):// is rewritten to ws(s):// and "/ws" is appended automatically.
stdlib + the existing `websockets` dependency only.
"""
import asyncio
import base64
import json
import logging
import os
import signal
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

import websockets

import tools

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("lumis.mac_agent")

# Default to the deployed Railway backend so the agent works out of the box;
# override with LUMIS_BACKEND_URL=http://localhost:8000 for local development.
DEFAULT_BACKEND_URL = "https://lumis-production-b878.up.railway.app"

# Seconds between reconnect attempts when the connection drops.
RECONNECT_DELAY_S = 3.0


def _ws_url() -> str:
    base = (os.getenv("LUMIS_BACKEND_URL") or DEFAULT_BACKEND_URL).strip()
    base = base.rstrip("/")
    if base.startswith("https://"):
        base = "wss://" + base[len("https://"):]
    elif base.startswith("http://"):
        base = "ws://" + base[len("http://"):]
    return base + "/ws"


# --------------------------------------------------------------------------- #
# iPhone <-> Mac linking
# --------------------------------------------------------------------------- #
HEARTBEAT_S = 15.0
_STATE_DIR = Path(os.path.expanduser("~/.lumis"))


def _http_base() -> str:
    return (os.getenv("LUMIS_BACKEND_URL") or DEFAULT_BACKEND_URL).strip().rstrip("/")


def _mac_id() -> str:
    """Stable per-machine id, persisted so re-launches keep the same identity."""
    _STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = _STATE_DIR / "mac_id"
    if path.exists():
        return path.read_text().strip()
    new_id = str(uuid.uuid4())
    path.write_text(new_id)
    return new_id


def _mac_name() -> str:
    name = socket.gethostname().replace(".local", "")
    return name or "Mac"


def _post(path: str, body: dict) -> dict:
    req = urllib.request.Request(
        _http_base() + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())


def _get(path: str) -> dict:
    with urllib.request.urlopen(_http_base() + path, timeout=10) as resp:
        return json.loads(resp.read().decode())


async def linking_loop() -> None:
    """Keep the Mac marked "online" for its paired phone.

    Pairing itself (showing the 6-digit code, confirming it) is owned by the
    signed-in Lumis Mac app, which calls the authenticated /link endpoints. This
    loop only sends heartbeats while a pairing exists, so the phone can tell the
    Mac is reachable. It identifies the Mac by the shared ~/.lumis/mac_id file.
    """
    mac_id = _mac_id()
    while True:
        try:
            linked = (await asyncio.to_thread(_get, f"/link/mac/{mac_id}")).get("linked", False)
            if linked:
                await asyncio.to_thread(_post, "/link/heartbeat",
                                        {"mac_id": mac_id, "mac_name": _mac_name()})
            await asyncio.sleep(HEARTBEAT_S if linked else 5)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            logger.debug("Heartbeat poll failed (%s); retrying.", exc)
            await asyncio.sleep(5)
        except asyncio.CancelledError:
            raise


# --------------------------------------------------------------------------- #
# Browser automation (Playwright)
#
# Replaces the old AppleScript Chrome control entirely — no "Allow JavaScript
# from Apple Events" toggle, no Automation/Accessibility prompts. One persistent
# Playwright browser + page lives in THIS agent's event loop and survives across
# tool calls in a session, so open_url → read_page → click → screenshot all act
# on the same live page. The browser is launched visibly so the user can watch.
# --------------------------------------------------------------------------- #
_playwright = None
_browser = None
_page = None
_browser_lock = asyncio.Lock()


async def get_browser_page():
    """Get or create the persistent, visible Playwright page."""
    global _playwright, _browser, _page
    from playwright.async_api import async_playwright  # lazy: only if browser used

    if _playwright is None:
        _playwright = await async_playwright().start()
    if _browser is None or not _browser.is_connected():
        _browser = await _playwright.chromium.launch(
            headless=False,            # visible so the user sees what Lumis does
            args=["--no-sandbox"],
        )
    if _page is None or _page.is_closed():
        context = await _browser.new_context(
            viewport={"width": 1280, "height": 800},
            user_agent=("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/120.0 Safari/537.36"),
        )
        _page = await context.new_page()
    return _page


async def close_browser() -> None:
    global _playwright, _browser, _page
    try:
        if _page:
            await _page.close()
        if _browser:
            await _browser.close()
        if _playwright:
            await _playwright.stop()
    except Exception:  # noqa: BLE001 - shutdown is best-effort
        pass
    _playwright = _browser = _page = None


async def tool_browser_open_url(args: dict) -> dict:
    url = str(args.get("url") or "").strip()
    if not url:
        return {"status": "error", "message": "browser.open_url requires a 'url'."}
    if not url.startswith(("http://", "https://")):
        # Bare domain → https; a multi-word query → Google search.
        if "." in url and " " not in url:
            url = "https://" + url
        else:
            url = "https://www.google.com/search?q=" + urllib.parse.quote(url)
    page = await get_browser_page()
    await page.goto(url, wait_until="domcontentloaded", timeout=20000)
    title = await page.title()
    return {
        "status": "success",
        "title": title or url,
        "message": f"Opened {title or url}.",
        "url": page.url,
        "speak": f"Opened {title or url}.",
        "data": {"url": page.url, "title": title},
    }


# Scrape the rendered page: visible text + clickable links (text + href) so the
# agent can SEE what's on the page and choose what to open/click.
_READ_PAGE_JS = """() => {
    const clone = document.body ? document.body.cloneNode(true) : null;
    if (clone) clone.querySelectorAll('script,style,nav,footer,aside,iframe,noscript')
                    .forEach(el => el.remove());
    const text = (clone ? clone.innerText : '').replace(/\\s+/g, ' ').slice(0, 4000);
    const seen = {}, links = [];
    const as = document.querySelectorAll('a[href]');
    for (let i = 0; i < as.length && links.length < 40; i++) {
        const a = as[i];
        const txt = (a.innerText || a.textContent || a.getAttribute('aria-label') || '')
                        .trim().replace(/\\s+/g, ' ');
        if (!txt || txt.length > 140) continue;
        const href = a.href;
        if (!href || href.indexOf('javascript:') === 0 || seen[href]) continue;
        seen[href] = 1; links.push({ text: txt, href });
    }
    return { title: document.title, url: location.href, text, links };
}"""


async def tool_browser_read_page(args: dict) -> dict:
    page = await get_browser_page()
    parsed = await page.evaluate(_READ_PAGE_JS)
    text = str(parsed.get("text") or "").strip()
    title = str(parsed.get("title") or "")
    url = str(parsed.get("url") or page.url)
    links = parsed.get("links") or []
    links_block = ""
    if links:
        links_block = "\n\nLinks on the page:\n" + "\n".join(
            f"{i}. {l.get('text', '')} — {l.get('href', '')}"
            for i, l in enumerate(links[:25])
        )
    summary = f"{title}\n{url}\n\n{text}{links_block}"
    return {
        "status": "success",
        "title": title or "Current Page",
        "message": text or f"Read {title or url}.",
        "detail": text[:3000],
        "summary": summary,
        "speak": f"You're on {title or url}.",
        "data": {"url": url, "title": title, "text": text, "links": links},
    }


async def tool_browser_fill_form(args: dict) -> dict:
    """Fill fields in the live page. IRREVERSIBLE; does NOT submit unless asked.

    Accepts either the list form  { fields: [{selector, value}] }  or the map
    form  { fields: { "selector_or_label": "value" } }. For each field it tries a
    CSS selector first, then placeholder text, then label text.
    """
    raw_fields = args.get("fields") or {}
    should_submit = bool(args.get("submit", False))
    pairs: list[tuple[str, str]] = []
    if isinstance(raw_fields, dict):
        pairs = [(str(k), str(v)) for k, v in raw_fields.items()]
    elif isinstance(raw_fields, list):
        pairs = [(str(f["selector"]), str(f.get("value", "")))
                 for f in raw_fields if isinstance(f, dict) and f.get("selector")]
    if not pairs:
        return {"status": "error",
                "message": "browser.fill_form requires a non-empty 'fields'."}

    page = await get_browser_page()
    filled = []
    for selector, value in pairs:
        try:
            el = page.locator(selector).first
            if await el.count() == 0:
                el = page.get_by_placeholder(selector).first
            if await el.count() == 0:
                el = page.get_by_label(selector).first
            await el.fill(value, timeout=5000)
            filled.append(selector)
        except Exception:  # noqa: BLE001 - skip a field that won't match
            continue
    if should_submit:
        await page.keyboard.press("Enter")
    summary = "Filled fields:\n" + "\n".join(f"• {s} = {v}" for s, v in pairs)
    return {
        "status": "success",
        "title": "Form Filled",
        "message": f"Filled {len(filled)} of {len(pairs)} field(s)"
                   + (" and submitted." if should_submit else "."),
        "detail": summary,
        "summary": summary,
        "speak": f"I filled {len(filled)} field{'s' if len(filled) != 1 else ''}."
                 + ("" if should_submit else " Review before submitting."),
        "data": {"filled": filled, "requested": len(pairs), "submitted": should_submit},
    }


async def tool_browser_click(args: dict) -> dict:
    """Click a button/link by CSS selector or by visible text."""
    selector = str(args.get("selector") or "").strip()
    text = str(args.get("text") or "").strip()
    if not selector and not text:
        return {"status": "error",
                "message": "browser.click requires a 'selector' or 'text'."}
    page = await get_browser_page()
    try:
        if selector:
            await page.locator(selector).first.click(timeout=8000)
            label = selector
        else:
            await page.get_by_text(text, exact=False).first.click(timeout=8000)
            label = text
    except Exception as exc:  # noqa: BLE001 - report a clean not-found error
        target = selector or f"text '{text}'"
        return {"status": "error", "title": "Click failed",
                "message": f"Couldn't click {target}: {exc}",
                "data": {"error": "not_found", "selector": selector, "text": text}}
    return {
        "status": "success",
        "title": "Clicked",
        "message": f"Clicked {('`'+selector+'`') if selector else repr(text)}.",
        "url": page.url,
        "speak": f"Clicked {label}.",
        "data": {"clicked": label, "url": page.url},
    }


async def tool_browser_screenshot(args: dict) -> dict:
    """Screenshot the current browser so the agent can SEE its state."""
    page = await get_browser_page()
    shot = await page.screenshot(type="png", full_page=False)
    return {
        "status": "success",
        "title": "Browser screenshot",
        "message": "Captured the current browser view.",
        "image_b64": base64.b64encode(shot).decode(),
        "speak": "I can see the browser now.",
        "data": {"url": page.url},
    }


BROWSER_TOOLS = {
    "browser.open_url": tool_browser_open_url,
    "browser.read_page": tool_browser_read_page,
    "browser.fill_form": tool_browser_fill_form,
    "browser.click": tool_browser_click,
    "browser.screenshot": tool_browser_screenshot,
}


async def _run_browser_tool(tool: str, args: dict) -> dict:
    """Run a Playwright browser tool in this agent's event loop, serialized so
    concurrent requests don't race on the single shared page. Always returns the
    standard result contract with `tool` + `elapsed_ms`."""
    fn = BROWSER_TOOLS[tool]
    start = time.monotonic()
    async with _browser_lock:
        try:
            result = await fn(args or {})
        except ImportError:
            result = {
                "status": "error",
                "message": "Playwright isn't installed yet. The Lumis Mac app "
                           "sets it up on first launch; reopen the app to finish.",
                "data": {"error": "playwright_missing"},
            }
        except Exception as exc:  # noqa: BLE001 - report failure truthfully
            logger.exception("Browser tool %s crashed", tool)
            result = {"status": "error",
                      "message": f"Browser tool {tool} failed: {exc}",
                      "data": {"error": str(exc)}}
    result.setdefault("tool", tool)
    result.setdefault("status", "success")
    result.setdefault("title", tool)
    result["elapsed_ms"] = round((time.monotonic() - start) * 1000, 1)
    return result


async def _handle_execute(ws, data: dict) -> None:
    """Run one execute_on_mac request locally and reply with mac_result."""
    action_id = data.get("action_id")
    tool = data.get("tool", "")
    args = data.get("args") or {}
    logger.info("Executing %s (action %s) args=%s", tool, action_id, args)

    # Browser tools run async in THIS event loop (persistent Playwright page).
    # Everything else is blocking (osascript/subprocess) — run it off the event
    # loop so the WebSocket keeps draining while a tool runs.
    try:
        if tool in BROWSER_TOOLS:
            result = await _run_browser_tool(tool, args)
        else:
            result = await asyncio.to_thread(tools.execute, tool, args)
    except Exception as exc:  # noqa: BLE001 - report failure truthfully
        logger.exception("Tool %s crashed", tool)
        result = {
            "tool": tool,
            "status": "error",
            "message": f"Mac agent failed to execute {tool}: {exc}",
            "title": tool,
            "data": {"error": str(exc)},
        }

    await ws.send(json.dumps({
        "event": "mac_result",
        "data": {"action_id": action_id, "result": result},
    }))
    logger.info("Returned result for action %s (%s).", action_id, result.get("status"))


async def _session(url: str) -> None:
    """Connect once, register, and service execute_on_mac events until closed."""
    async with websockets.connect(url, max_size=None, ping_interval=20) as ws:
        await ws.send(json.dumps({"event": "register", "role": "mac"}))
        logger.info("Connected and registered as Mac agent: %s", url)

        async for raw in ws:
            try:
                msg = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if not isinstance(msg, dict):
                continue
            # We only act on execute_on_mac; all other broadcasts are ignored.
            if msg.get("event") == "execute_on_mac":
                # Run concurrently so a slow tool doesn't block the next request.
                asyncio.create_task(_handle_execute(ws, msg.get("data") or {}))


async def run() -> None:
    url = _ws_url()
    logger.info("Lumis Mac agent starting. Backend: %s", url)
    # Run iPhone<->Mac linking concurrently with the WS service loop.
    link_task = asyncio.create_task(linking_loop())
    try:
        while True:
            try:
                await _session(url)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - keep the agent alive
                logger.warning("Connection lost (%s). Reconnecting in %.0fs…",
                               exc, RECONNECT_DELAY_S)
            else:
                logger.info("Connection closed. Reconnecting in %.0fs…", RECONNECT_DELAY_S)
            await asyncio.sleep(RECONNECT_DELAY_S)
    finally:
        link_task.cancel()
        await close_browser()


def main() -> None:
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    task = loop.create_task(run())

    # Clean shutdown on Ctrl-C / SIGTERM (e.g. when the Mac app quits us).
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, task.cancel)
        except NotImplementedError:  # pragma: no cover - not on all platforms
            pass

    try:
        loop.run_until_complete(task)
    except (KeyboardInterrupt, asyncio.CancelledError):
        logger.info("Lumis Mac agent stopped.")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
