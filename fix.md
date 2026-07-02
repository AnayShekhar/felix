# Lumis — General-Purpose Browser Reliability + Real Browser Handoff

This fixes two things across ALL browser tools, not just YouTube: reliability of
clicks/navigation on any website, and giving the user a way to open what Lumis did
in their own real Chrome/Safari — for every browser action, not just account-based
ones. Also adds a way to verify Chrome extension cookie sync actually worked.

---

## Part 1 — Reliable navigation and interaction (works on any site)

### The problem
`browser.click`, `browser.open_url`, and `browser.fill_form` currently fire
immediately without confirming the page/element is actually ready, so they
succeed or fail inconsistently depending on page load speed, layout shifts, and
site-specific quirks. This isn't a YouTube-specific bug — it'll happen on every
site under real network conditions.

### Fix — proper wait strategy in `backend/browser_tools.py`

Replace the navigation and click logic with a general-purpose reliable pattern
that works regardless of which site is being controlled:

```python
async def reliable_goto(page: Page, url: str, timeout: int = 20000) -> None:
    """Navigate and wait for the page to be meaningfully interactive, not just loaded."""
    await page.goto(url, wait_until="domcontentloaded", timeout=timeout)
    try:
        await page.wait_for_load_state("networkidle", timeout=5000)
    except Exception:
        pass  # Some sites (YouTube, infinite scroll pages) never go fully idle — that's fine
    await page.wait_for_timeout(500)  # let any final JS-driven layout settle


async def reliable_click(page: Page, selector: str = None, text: str = None, timeout: int = 10000) -> bool:
    """
    Attempts a click with multiple fallback strategies, in order:
    1. Exact CSS selector
    2. Visible text match
    3. Accessible role/label match
    4. First matching element if multiple candidates exist, preferring visible ones
    Returns True if a click succeeded, False otherwise — never raises.
    """
    strategies = []

    if selector:
        strategies.append(lambda: page.locator(selector).first)
    if text:
        strategies.append(lambda: page.get_by_text(text, exact=False).first)
        strategies.append(lambda: page.get_by_role("button", name=text).first)
        strategies.append(lambda: page.get_by_role("link", name=text).first)
        strategies.append(lambda: page.get_by_label(text).first)

    for build_locator in strategies:
        try:
            locator = build_locator()
            await locator.wait_for(state="visible", timeout=timeout / len(strategies))
            await locator.scroll_into_view_if_needed()
            await locator.click(timeout=3000)
            return True
        except Exception:
            continue

    return False


async def reliable_fill(page: Page, selector_or_label: str, value: str, timeout: int = 5000) -> bool:
    """Fills a field, trying selector, then placeholder, then label, then name attribute."""
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
```

### Update every browser tool to use these helpers

```python
async def tool_browser_open_url(args: dict, user_id: str) -> dict:
    page, session_id = await get_page_for_user(user_id)
    try:
        url = args["url"]
        if not url.startswith("http"):
            url = "https://" + url
        await reliable_goto(page, url)
        title = await page.title()
        current_url = page.url
        return {
            "status": "success",
            "title": f"Opened {title}",
            "message": f"Navigated to {title}",
            "url": current_url,          # the REAL final URL after any redirects
            "speak": f"Opened {title}."
        }
    except Exception as e:
        return {"status": "error", "message": f"Couldn't open that page: {e}"}
    finally:
        await close_cloud_session(session_id)


async def tool_browser_click(args: dict, user_id: str) -> dict:
    page, session_id = await get_page_for_user(user_id)
    try:
        success = await reliable_click(page, selector=args.get("selector"), text=args.get("text"))
        if not success:
            return {
                "status": "error",
                "message": f"Couldn't find or click {'`'+args.get('selector','')+'`' if args.get('selector') else repr(args.get('text'))}",
                "url": page.url
            }
        await page.wait_for_timeout(800)  # let click's effect (navigation, popup, etc.) settle
        return {
            "status": "success",
            "title": "Clicked",
            "message": "Done",
            "url": page.url,             # wherever the click actually took us
            "speak": "Done."
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        await close_cloud_session(session_id)


async def tool_browser_fill_form(args: dict, user_id: str) -> dict:
    page, session_id = await get_page_for_user(user_id)
    try:
        fields = args.get("fields", {})
        filled = []
        failed = []
        for key, value in fields.items():
            success = await reliable_fill(page, key, value)
            (filled if success else failed).append(key)

        if args.get("submit") and filled:
            await page.keyboard.press("Enter")
            await page.wait_for_timeout(800)

        return {
            "status": "success" if filled else "error",
            "title": "Form filled" if filled else "Couldn't fill form",
            "message": f"Filled: {', '.join(filled) or 'none'}. Failed: {', '.join(failed) or 'none'}.",
            "url": page.url,
            "speak": "Done." if filled else "I couldn't find those fields on this page."
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        await close_cloud_session(session_id)
```

### Verification screenshot after every interactive action

Add automatic post-action screenshots so the agent can visually confirm the
result before reporting success — this catches silent failures (click landed on
the wrong element, page didn't navigate, etc.):

```python
async def verify_with_screenshot(page: Page) -> str:
    screenshot_bytes = await page.screenshot(type="png")
    import base64
    return base64.b64encode(screenshot_bytes).decode()
```

Call this at the end of `tool_browser_click` and `tool_browser_fill_form`, attach
`image_b64` to the result. `agent.py` already knows (from earlier work) to feed
any `image_b64` in a tool result back into the agent's context as a vision
message — so the agent sees what actually happened and can catch a failed click
even when the click "succeeded" technically but did the wrong thing.

---

## Part 2 — Real browser handoff for every site, not just account-based tools

### The problem
Right now only some tools return a `url` the iOS app can open. Every single
browser tool should return the real, final URL — whatever site Lumis ended up on
— so the user can always open exactly what Lumis was looking at in their own
Chrome or Safari.

### Fix — universal `url` field

Audit every tool in `backend/browser_tools.py` and `backend/google_tools.py`.
Every single one that touches a URL (browser tools) or produces a link (Google
Docs/Sheets/Calendar) MUST include `"url"` in its result dict, set to the real,
live, correct link — not a placeholder, not the session's internal Browserbase
URL. This was already true for some tools; make it universally true for all of them.

### iOS — universal "Open in Chrome" / "Open in Safari"

Update `LumisResultCard` in `HomeView.swift` (or wherever result cards render) so
that ANY result with a non-nil `url` field shows an open button — not just for
certain action types:

```swift
struct LumisResultCard: View {
    let result: ActionResult

    var body: some View {
        HStack {
            // ... existing icon, title, description ...

            if let url = result.url {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    Text("Open")
                        .font(LumisTypography.bodyMedium)
                        .foregroundColor(LumisColors.powderBlue)
                }
            }
        }
    }
}
```

Remove any conditional logic that only shows "Open" for specific `actionType`
values (like only for spreadsheets or docs) — if a `url` exists, show the button,
regardless of which tool produced it. This makes "open YouTube, click the first
video" behave the same way: the result includes the real YouTube video URL that
was reached inside the cloud browser, and tapping "Open" launches that exact
video in the user's own Safari/Chrome, picking up right where Lumis left off.

### Be explicit with the user about what "Open" means

Add a one-time explainer (first time a result card with an "Open" button appears)
using a lightweight tooltip or one-line caption under the button:

```swift
Text("Opens in your own browser")
    .font(LumisTypography.caption)
    .foregroundColor(LumisColors.carbonBlack.opacity(0.4))
```

This sets the right expectation — the action happened in the cloud, tapping Open
takes YOU to the same place, it isn't a live mirror of the cloud session.

### Update agent_prompt.py

Add this rule so the agent always captures and returns the real URL:

```
ALWAYS RETURN THE REAL URL
Every browser-based tool result must include the exact, final URL the cloud
browser ended up on — after any redirects, searches, or clicks. This lets the
user open the same page in their own browser. Never omit this field for browser
tools. If a tool result doesn't include a url, treat that as a signal the tool
implementation is incomplete, not something to work around.
```

---

## Part 3 — Verify Chrome extension cookie sync actually worked

### New debug endpoint — `backend/routes.py`

```python
@app.get("/connect/verify/{service}")
async def verify_service_cookies(service: str, user=Depends(get_current_user)):
    """
    Opens the user's persistent Browserbase context and checks whether cookies
    exist for the given service's domain. Returns cookie NAMES only, never values.
    """
    from cloud_browser import get_or_create_user_context, get_cloud_page, close_cloud_session

    domain_map = {
        "gmail": "google.com",
        "sheets": "google.com",
        "notion": "notion.so",
        "linkedin": "linkedin.com",
        "slack": "slack.com",
        "airtable": "airtable.com",
        "spotify": "spotify.com",
    }
    domain = domain_map.get(service, service)

    context_id = await get_or_create_user_context(user.id)
    page, session_id = await get_cloud_page(user.id, context_id)
    try:
        cookies = await page.context.cookies()
        matching = [c for c in cookies if domain in c["domain"]]
        cookie_names = [c["name"] for c in matching]
        return {
            "service": service,
            "domain": domain,
            "cookie_count": len(matching),
            "cookie_names": cookie_names,   # names only — never expose values
            "likely_synced": len(matching) > 0
        }
    finally:
        await close_cloud_session(session_id)
```

### iOS — add a "Verify connection" option

In `SettingsView.swift`, under each connected service row, add a small
"Verify" text button that calls this endpoint and shows a quick result:

```swift
Button("Verify") {
    Task {
        let result: VerifyResponse = try await apiClient.get("/connect/verify/\(service.id)")
        verifyMessage = result.likelySynced
            ? "✓ \(result.cookieCount) cookies found — should work"
            : "⚠ No cookies found — try reconnecting in the extension"
    }
}
.font(LumisTypography.caption)
.foregroundColor(LumisColors.carbonBlack.opacity(0.4))
```

```swift
struct VerifyResponse: Codable {
    let service: String
    let domain: String
    let cookieCount: Int
    let cookieNames: [String]
    let likelySynced: Bool

    enum CodingKeys: String, CodingKey {
        case service, domain
        case cookieCount = "cookie_count"
        case cookieNames = "cookie_names"
        case likelySynced = "likely_synced"
    }
}
```

This gives you (and eventually users) a direct, honest way to check "did the
sync actually work" instead of only finding out indirectly when an agent action
succeeds or fails.

---

## Part 4 — Verification

- [ ] "Open YouTube and click the first video" succeeds consistently across
      repeated tries (run it 5 times in a row, should succeed at least 4/5 —
      flakiness should be dramatically reduced, not necessarily zero on JS-heavy
      sites like YouTube)
- [ ] Result card after this action includes a working "Open" button
- [ ] Tapping "Open" launches the exact same YouTube video in the user's real
      Safari/Chrome
- [ ] Test the same "Open" behavior on at least 3 different kinds of actions:
      a browser click (YouTube), a Google Sheets edit, and a Notion page creation
      — all three should show "Open" and all three should open the correct real
      destination
- [ ] `browser.fill_form` on a real form (e.g. a simple contact form) succeeds
      using label-based fallback even when no exact CSS selector is given
- [ ] `/connect/verify/gmail` (or any connected service) returns
      `likely_synced: true` with cookie names, after connecting via the extension
- [ ] `/connect/verify/{service}` for an unconnected service returns
      `likely_synced: false` with zero cookies, without crashing
- [ ] Settings screen "Verify" button shows a clear success/failure message per service