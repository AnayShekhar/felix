"""Lumis cloud tool layer.

After the Mac-agent removal, Lumis executes entirely in the cloud. Tools split
three ways (see TOOL_REGISTRY "runs_on"):

  - "google_api"    → backend/google_tools.py (Docs, Sheets, Gmail, Calendar,
                       Tasks, People, Drive), authenticated per user.
  - "cloud_browser" → backend/browser_tools.py (Browserbase), for browser.*,
                       media/Spotify, Notion/Slack/LinkedIn/Airtable.
  - "ios_native"    → this file, returns an "ios_action" URL scheme the phone
                       opens directly.

This module also owns the web.* research tools (keyless HTTP, no browser needed)
and the shared tool metadata registry consulted by the agent for routing +
service gating. There is NO AppleScript or local-file execution here anymore —
all of that left with the Mac agent.
"""
import logging
import os
import re
import urllib.parse

logger = logging.getLogger("lumis.tools")

# Browser-like UA so search engines / sites return real HTML to the research agent.
_WEB_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

# Groq is the ONLY AI provider. GROQ_API_KEY is the only required key.
# llama-4-scout was shut down on Groq (2026-07-17); default to multimodal Qwen.
DEFAULT_GROQ_MODEL = "qwen/qwen3.6-27b"
GROQ_MODEL = os.getenv("GROQ_MODEL", DEFAULT_GROQ_MODEL)


class ToolError(Exception):
    """A tool failed in a non-retryable way (e.g. bad input)."""


# --------------------------------------------------------------------------- #
# Groq helpers (used by the research agent + image OCR)
# --------------------------------------------------------------------------- #
def _groq_client():
    from groq import Groq

    key = os.environ.get("GROQ_API_KEY")
    if not key:
        raise ToolError("This tool requires GROQ_API_KEY to be set.")
    return Groq(api_key=key)


def _groq_kwargs(model: str) -> dict:
    # Qwen 3.6 emits reasoning by default; disable so tool helpers stay clean.
    if model.startswith("qwen/"):
        return {"reasoning_effort": "none"}
    return {}


def _strip_think(text: str) -> str:
    """Drop accidental <think>…</think> blocks if a model still emits them."""
    return re.sub(r"<think>[\s\S]*?</think>", "", text, flags=re.I).strip()


def _groq_vision(image_b64: str, prompt: str, max_tokens: int = 1000) -> str:
    """Send a base64 image + prompt to Groq's vision model, return its text."""
    client = _groq_client()
    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[{
            "role": "user",
            "content": [
                {"type": "image_url",
                 "image_url": {"url": f"data:image/png;base64,{image_b64}"}},
                {"type": "text", "text": prompt},
            ],
        }],
        max_tokens=max_tokens,
        **_groq_kwargs(GROQ_MODEL),
    )
    return _strip_think(response.choices[0].message.content or "")


def _groq_text(prompt: str, max_tokens: int = 1200) -> str:
    client = _groq_client()
    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
        **_groq_kwargs(GROQ_MODEL),
    )
    return _strip_think(response.choices[0].message.content or "")


def _first_two_sentences(text: str) -> str:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return " ".join(parts[:2]).strip()


# --------------------------------------------------------------------------- #
# Web search / fetch / research (keyless HTTP — no browser, no auth)
# --------------------------------------------------------------------------- #
def _unwrap_ddg(href: str) -> str:
    if "uddg=" in href:
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
        href = urllib.parse.unquote(qs.get("uddg", [href])[0])
    if href.startswith("//"):
        href = "https:" + href
    return href


def _duckduckgo_search(query: str, limit: int = 5) -> list:
    import requests
    from bs4 import BeautifulSoup

    resp = requests.post("https://html.duckduckgo.com/html/", data={"q": query},
                         headers={"User-Agent": _WEB_UA}, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    results = []
    links = soup.select("a.result__a") or soup.select(".result__a") \
        or soup.select("a[href*='uddg=']")
    for link in links:
        href = _unwrap_ddg(link.get("href", ""))
        if not href or "duckduckgo.com/y.js" in href or "ad_domain=" in href:
            continue
        container = link.find_parent(class_="result") or link.parent
        snippet_el = container.select_one(".result__snippet") if container else None
        snippet = snippet_el.get_text(" ", strip=True) if snippet_el else ""
        title = link.get_text(" ", strip=True)
        if href.startswith("http") and title:
            results.append({"title": title, "url": href, "snippet": snippet})
        if len(results) >= limit:
            break
    return results


def _ddg_lite_search(query: str, limit: int = 5) -> list:
    import requests
    from bs4 import BeautifulSoup

    resp = requests.post("https://lite.duckduckgo.com/lite/", data={"q": query},
                         headers={"User-Agent": _WEB_UA}, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    results = []
    for link in soup.select("a.result-link"):
        href = _unwrap_ddg(link.get("href", ""))
        title = link.get_text(" ", strip=True)
        if href.startswith("http") and title:
            results.append({"title": title, "url": href, "snippet": ""})
        if len(results) >= limit:
            break
    return results


def _ddg_instant_answer(query: str, limit: int = 5) -> list:
    import requests

    resp = requests.get("https://api.duckduckgo.com/",
                        params={"q": query, "format": "json", "no_html": 1,
                                "skip_disambig": 1},
                        headers={"User-Agent": _WEB_UA}, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    results = []

    def add(text, url):
        if url and text:
            results.append({"title": text[:120], "url": url, "snippet": text})

    if data.get("AbstractURL") and data.get("AbstractText"):
        add(data.get("Heading") or data["AbstractText"], data["AbstractURL"])
    for topic in data.get("RelatedTopics", []):
        if len(results) >= limit:
            break
        if "Topics" in topic:
            for sub in topic["Topics"]:
                if len(results) >= limit:
                    break
                add(sub.get("Text", ""), sub.get("FirstURL", ""))
        else:
            add(topic.get("Text", ""), topic.get("FirstURL", ""))
    return results[:limit]


def _wikipedia_search(query: str, limit: int = 5) -> list:
    import requests

    resp = requests.get("https://en.wikipedia.org/w/api.php",
                        params={"action": "opensearch", "search": query,
                                "limit": limit, "namespace": 0, "format": "json"},
                        headers={"User-Agent": _WEB_UA}, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    titles, descriptions, urls = data[1], data[2], data[3]
    results = []
    for i, url in enumerate(urls):
        title = titles[i] if i < len(titles) else url
        snippet = descriptions[i] if i < len(descriptions) else ""
        results.append({"title": title, "url": url, "snippet": snippet})
    return results[:limit]


def _search_web(query: str, limit: int = 5) -> list:
    for backend in (_duckduckgo_search, _ddg_lite_search, _ddg_instant_answer,
                    _wikipedia_search):
        try:
            results = backend(query, limit)
        except Exception as exc:  # noqa: BLE001
            logger.info("Search backend %s failed for %r: %s",
                        backend.__name__, query, exc)
            continue
        if results:
            return results[:limit]
    return []


def web_search(args: dict) -> dict:
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("web.search requires a 'query'.")
    try:
        results = _search_web(query, 5)
    except Exception as exc:  # noqa: BLE001
        return {"tool": "web.search", "status": "error",
                "message": f'Web search failed for "{query}": {exc}', "title": query,
                "data": {"query": query, "results": [], "error": str(exc)}}
    return {"tool": "web.search", "status": "success",
            "message": f'Found {len(results)} result(s) for "{query}".', "title": query,
            "detail": "\n".join(f"{r['title']} — {r['url']}" for r in results),
            "data": {"query": query, "results": results}}


def web_fetch_page(args: dict) -> dict:
    url = str(args.get("url") or "").strip()
    if not url:
        raise ToolError("web.fetch_page requires a 'url'.")
    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    import requests
    from bs4 import BeautifulSoup

    resp = requests.get(url, headers={"User-Agent": _WEB_UA}, timeout=20)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    for tag in soup(["script", "style", "noscript", "header", "footer", "nav", "form"]):
        tag.decompose()
    page_title = soup.title.get_text(strip=True) if soup.title else url
    text = soup.get_text("\n", strip=True)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    truncated = text[:3000]
    return {"tool": "web.fetch_page", "status": "success",
            "message": f"Fetched {len(truncated)} chars from {url}.", "title": page_title,
            "detail": truncated, "url": url,
            "data": {"url": url, "title": page_title, "text": truncated,
                     "length": len(text), "truncated": len(text) > 3000}}


def _save_research_doc(title: str, content: str, user_id: str):
    """Save research to a Google Doc if the user has Google connected.

    Returns (saved: bool, url: Optional[str]). Never raises.
    """
    try:
        import google_tools

        res = google_tools.execute_google_tool(
            "docs.create_document", {"title": title, "content": content}, user_id)
        if res.get("status") == "success":
            return True, (res.get("data") or {}).get("url")
    except Exception as exc:  # noqa: BLE001
        logger.info("Research doc save skipped: %s", exc)
    return False, None


def web_research(args: dict, user_id: str = "") -> dict:
    """Research a topic end-to-end; save the synthesis as a Google Doc if possible."""
    topic = str(args.get("topic") or args.get("query") or "").strip()
    if not topic:
        raise ToolError("web.research requires a 'topic'.")
    output_format = str(args.get("output_format") or "note").strip().lower()
    if output_format not in ("note", "document", "summary"):
        output_format = "note"

    sources, seen = [], set()
    for q in (topic, f"{topic} overview", f"{topic} latest", f"{topic} explained"):
        try:
            for r in _search_web(q, 5):
                u = r.get("url")
                if u and u not in seen:
                    seen.add(u)
                    sources.append(r)
        except Exception as exc:  # noqa: BLE001
            logger.info("Research search failed for %r: %s", q, exc)
        if len(sources) >= 6:
            break

    if not sources:
        try:
            knowledge = _groq_text(
                f"Write a {output_format} about {topic}. Be specific, accurate, "
                "and well-organized. If unsure about any detail, say so.").strip()
        except Exception as exc:  # noqa: BLE001
            return {"tool": "web.research", "status": "error",
                    "message": f'Could not research "{topic}".', "title": topic,
                    "speak": f"I couldn't research {topic} right now.",
                    "data": {"topic": topic, "sources": []}}
        disclaimer = ("Note: from AI knowledge, not live sources — web search "
                      "returned nothing, so details may be out of date.")
        content = f"{disclaimer}\n\n{knowledge}"
        saved, url = _save_research_doc(f"Research: {topic}", content, user_id)
        return {"tool": "web.research", "status": "success",
                "message": f'Researched "{topic}" from AI knowledge.', "title": f"Research: {topic}",
                "detail": knowledge[:1000], "url": url,
                "speak": f"Here's a summary of {topic} from what I know.",
                "summary": f"{disclaimer}\n\n{knowledge[:500]}",
                "data": {"topic": topic, "sources": [], "from_ai_knowledge": True,
                         "doc_saved": saved, "url": url}}

    fetched = []
    for s in sources[:3]:
        try:
            page = web_fetch_page({"url": s["url"]})
            fetched.append({"title": s.get("title") or page["data"].get("title"),
                            "url": s["url"], "text": page["data"].get("text", "")})
        except Exception as exc:  # noqa: BLE001
            logger.info("Research fetch failed for %s: %s", s.get("url"), exc)

    source_lines = "\n".join(f"[{i + 1}] {s.get('title')} ({s.get('url')})"
                             for i, s in enumerate(sources[:6]))
    corpus = "\n\n".join(f"SOURCE [{i + 1}] {f.get('title')} ({f.get('url')}):\n{f.get('text')}"
                         for i, f in enumerate(fetched))
    try:
        synthesis = _groq_text(
            f"Synthesize this into a {output_format} about {topic}. "
            "Be specific and cite sources by their [number].\n\n"
            f"SOURCES:\n{source_lines}\n\nCONTENT:\n{corpus}")
    except Exception as exc:  # noqa: BLE001
        snippets = "\n".join(f"- {s.get('title')}: {s.get('snippet') or s.get('url')}"
                             for s in sources[:5])
        synthesis = (f"Research summary for {topic} (auto-synthesis unavailable):\n\n"
                     f"{snippets}\n\nSources:\n{source_lines}")
    if not synthesis.strip():
        synthesis = f"No content synthesized for {topic}.\n\nSources:\n{source_lines}"

    content = f"{synthesis}\n\nSources:\n{source_lines}"
    saved, url = _save_research_doc(f"Research: {topic}", content, user_id)
    saved_msg = (f'Researched "{topic}" and saved a Google Doc.' if saved
                 else f'Researched "{topic}" ({output_format}).')
    return {"tool": "web.research", "status": "success", "message": saved_msg,
            "title": f"Research: {topic}", "detail": synthesis[:1000], "url": url,
            "speak": ("Done — I saved a doc summarizing it." if saved
                      else f"Here's what I found on {topic}."),
            "summary": synthesis[:500],
            "data": {"topic": topic, "output_format": output_format,
                     "synthesis": synthesis, "sources": sources[:6],
                     "fetched_count": len(fetched), "doc_saved": saved, "url": url}}


# --------------------------------------------------------------------------- #
# iOS native actions — return an "ios_action" URL scheme the phone opens
# --------------------------------------------------------------------------- #
def _ios_action(tool: str, title: str, message: str, speak: str, url: str,
                fallback_url: str = "") -> dict:
    return {"status": "ios_action", "tool": tool, "title": title, "message": message,
            "speak": speak, "url": url, "fallback_url": fallback_url, "elapsed_ms": 0,
            "data": {"url": url, "fallback_url": fallback_url}}


def ios_create_reminder(args: dict) -> dict:
    title = str(args.get("title") or "").strip()
    if not title:
        raise ToolError("ios.create_reminder requires a 'title'.")
    due = str(args.get("due_date") or "").strip()
    # ReminderKit URL scheme only reliably accepts title; include due date in
    # the title suffix so the phone still surfaces the timing, and put the
    # raw due value in data for clients that can do better.
    display = title if not due else f"{title} (due {due})"
    url = "x-apple-reminderkit://create?" + urllib.parse.urlencode({"title": display})
    fallback = "shortcuts://run-shortcut?" + urllib.parse.urlencode(
        {"name": "Add Reminder", "input": display})
    msg = f'Adding a reminder "{title}"' + (f" due {due}." if due else ".")
    result = _ios_action("ios.create_reminder", "New Reminder", msg,
                         f"Adding the reminder {title}.", url, fallback)
    result["data"] = {**(result.get("data") or {}), "title": title, "due_date": due or None}
    return result


def ios_create_note(args: dict) -> dict:
    title = str(args.get("title") or "").strip()
    content = str(args.get("content") or "").strip()
    if not title and not content:
        raise ToolError("ios.create_note requires a 'title' or 'content'.")
    body = "\n".join(p for p in (title, content) if p)
    url = "mobilenotes://new?" + urllib.parse.urlencode({"body": body})
    return _ios_action("ios.create_note", title or "New Note",
                       f'Creating a note "{title or content[:30]}" on your phone.',
                       "Creating a note on your phone.", url)


def ios_open_maps(args: dict) -> dict:
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("ios.open_maps requires a 'query'.")
    url = "maps://?" + urllib.parse.urlencode({"q": query})
    return _ios_action("ios.open_maps", "Maps", f"Opening Maps for {query}.",
                       f"Opening Maps for {query}.", url)


def ios_send_message_draft(args: dict) -> dict:
    contact = str(args.get("contact") or "").strip()
    message = str(args.get("message") or "").strip()
    if not contact:
        raise ToolError("ios.send_message_draft requires a 'contact'.")
    url = f"sms:{urllib.parse.quote(contact)}&body={urllib.parse.quote(message)}"
    return _ios_action("ios.send_message_draft", "New Message",
                       f"Opening a message draft to {contact}.",
                       f"Opening a message draft to {contact}.", url)


_IOS_TOOLS = {
    "ios.create_reminder": ios_create_reminder,
    "ios.create_note": ios_create_note,
    "ios.open_maps": ios_open_maps,
    "ios.send_message_draft": ios_send_message_draft,
    "ios.draft_message": ios_send_message_draft,  # doc alias
}


def execute_ios_tool(tool: str, args: dict, user_id: str = "") -> dict:
    fn = _IOS_TOOLS.get(tool)
    if fn is None:
        return {"tool": tool, "status": "error",
                "message": f"Unknown iOS tool: {tool}", "data": {}}
    try:
        return fn(args or {})
    except ToolError as exc:
        return {"tool": tool, "status": "error", "message": str(exc),
                "speak": str(exc), "data": {"error": str(exc)}}


def execute_cloud_tool(tool: str, args: dict, user_id: str = "") -> dict:
    """Run a cloud web.* tool synchronously (used by the agent + browser_tools)."""
    args = args or {}
    try:
        if tool == "web.search":
            return web_search(args)
        if tool == "web.fetch_page":
            return web_fetch_page(args)
        if tool == "web.research":
            return web_research(args, user_id)
    except ToolError as exc:
        return {"tool": tool, "status": "error", "message": str(exc),
                "speak": str(exc), "data": {"error": str(exc)}}
    except Exception as exc:  # noqa: BLE001
        return {"tool": tool, "status": "error", "message": f"{tool} failed: {exc}",
                "data": {"error": str(exc)}}
    return {"tool": tool, "status": "error", "message": f"Unknown cloud tool: {tool}",
            "data": {}}


# --------------------------------------------------------------------------- #
# Tool registry — every entry runs on google_api | cloud_browser | ios_native.
# No entry runs on the (removed) Mac agent.
# --------------------------------------------------------------------------- #
TOOL_REGISTRY = {
    # Google API tools
    "docs.create_document":     {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "docs.append_text":         {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.create_spreadsheet": {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.add_row":           {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.read_sheet":        {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.edit_cell":         {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "gmail.draft_email":        {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "gmail.update_draft":       {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "gmail.send_draft":         {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},
    "gmail.send_email":         {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},
    "gmail.read_inbox":         {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "calendar.create_event":    {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "calendar.read_today":      {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "tasks.create_task":        {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "tasks.complete_task":      {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},
    "people.search_contacts":   {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "drive.search_files":       {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "drive.move_file":          {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},

    # Cloud browser tools
    "browser.open_url":         {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.read_page":        {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.click":            {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.fill_form":        {"runs_on": "cloud_browser", "irreversible": True,  "requires_service": None},
    "browser.screenshot":       {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "media.open_spotify":       {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "spotify"},
    "media.play_pause":         {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "spotify"},
    "notion.create_page":       {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "notion"},
    "notion.append_to_page":    {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "notion"},
    "linkedin.post_update":     {"runs_on": "cloud_browser", "irreversible": True,  "requires_service": "linkedin"},
    "slack.send_message":       {"runs_on": "cloud_browser", "irreversible": True,  "requires_service": "slack"},
    "airtable.add_record":      {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "airtable"},

    # Web (no auth, no browser)
    "web.search":               {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "web.fetch_page":           {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "web.research":             {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},

    # iOS native
    "ios.create_reminder":      {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.create_note":          {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.open_maps":            {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.send_message_draft":   {"runs_on": "ios_native", "irreversible": True,  "requires_service": None},
    "ios.draft_message":        {"runs_on": "ios_native", "irreversible": True,  "requires_service": None},
}

# Derived set of irreversible tools (kept for compatibility with consumers that
# imported IRREVERSIBLE_TOOLS directly).
IRREVERSIBLE_TOOLS = {name for name, meta in TOOL_REGISTRY.items()
                      if meta.get("irreversible")}


def build_undo(tool: str, args: dict, result: dict):
    """Undo is unavailable in the cloud architecture (no local scripting)."""
    return False, None


def run_undo(undo_script: str) -> dict:
    return {"status": "error", "message": "Undo is not supported in this version."}
