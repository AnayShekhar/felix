"""Felix macOS execution engine.

Each tool maps 1:1 to a real system action via AppleScript (`osascript`),
the `open` command, or Chrome. There are no fake outputs here — every
function performs a visible action on the host Mac.

Phase 1 hardening: every tool now returns the structured contract
``{"status": "success" | "error", "message": str, "data": dict, ...}``.
Execution is wrapped with retry-with-backoff and per-call latency timing
(``elapsed_ms``) so the Mac agent is fast and fails loudly instead of
silently. Legacy display keys (``tool``, ``title``, ``detail``, ``url``)
are preserved so existing WebSocket consumers keep working unchanged.
"""
import base64
import json
import logging
import os
import re
import shutil
import subprocess
import time
import urllib.parse

logger = logging.getLogger("felix.tools")

# Browser-like UA so search engines / sites return real HTML to the research agent.
_WEB_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

CHROME = "Google Chrome"

# Retry policy for tools that drive external apps (Notes, Numbers, Spotify,
# Chrome, Google APIs). Transient AppleScript/UI failures are common, so we
# retry a couple of times with a short backoff before surfacing an error.
MAX_RETRIES = 2          # total attempts = MAX_RETRIES + 1
RETRY_BACKOFF_S = 0.5    # 500ms between attempts

# Persistent Apple Numbers expense file so repeated receipts append to one doc.
EXPENSE_FILE = os.path.expanduser(
    os.getenv("FELIX_EXPENSE_FILE", "~/Documents/Felix Expenses.numbers")
)
EXPENSE_HEADERS = ["Date", "Merchant", "Category", "Amount", "Notes"]


class ToolError(Exception):
    """A tool failed in a non-retryable way (e.g. bad input)."""


def _osascript(script: str, timeout: float = 30.0) -> str:
    """Run an AppleScript snippet, returning stdout.

    Raises ``RuntimeError`` with the captured stderr on failure so the real
    AppleScript error message surfaces to the UI instead of being swallowed.
    """
    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"AppleScript timed out after {timeout:.0f}s") from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "unknown error").strip()
        raise RuntimeError(f"AppleScript failed: {detail}")
    return (proc.stdout or "").strip()


def _as_escape(value: str) -> str:
    """Escape a Python string for safe embedding inside an AppleScript string."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _shell(cmd: list, timeout: float = 30.0) -> str:
    """Run a shell command (list form, no shell injection), return stdout.

    Raises ``RuntimeError`` with captured stderr on non-zero exit so the real
    error surfaces to the UI instead of being swallowed.
    """
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"Command timed out after {timeout:.0f}s") from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "unknown error").strip()
        raise RuntimeError(f"Command failed: {detail}")
    return (proc.stdout or "").strip()


def _clamp(value, lo: int, hi: int) -> int:
    """Clamp a numeric arg to an integer in [lo, hi]."""
    try:
        n = int(round(float(value)))
    except (TypeError, ValueError):
        n = lo
    return max(lo, min(hi, n))


# Groq is the ONLY AI provider (Fix 6). GROQ_API_KEY is the only required key.
GROQ_MODEL = os.getenv("GROQ_MODEL", "meta-llama/llama-4-scout-17b-16e-instruct")


def _groq_client():
    """Build a Groq client, raising ToolError if the key is missing."""
    from groq import Groq

    key = os.environ.get("GROQ_API_KEY")
    if not key:
        raise ToolError("This tool requires GROQ_API_KEY to be set.")
    return Groq(api_key=key)


def _groq_vision(image_b64: str, prompt: str, max_tokens: int = 1000) -> str:
    """Send a base64 PNG + prompt to Groq's vision model and return its text.

    Used by the screen-awareness tools. Raises ``ToolError`` if no API key is
    configured so the failure surfaces in the UI rather than silently.
    """
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
    )
    return (response.choices[0].message.content or "").strip()


def _groq_text(prompt: str, max_tokens: int = 1200) -> str:
    """Send a text-only prompt to Groq and return its response text."""
    client = _groq_client()
    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
    )
    return (response.choices[0].message.content or "").strip()


def _first_two_sentences(text: str) -> str:
    """Return the first 1-2 sentences of a block of text for a spoken summary."""
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return " ".join(parts[:2]).strip()


# ----------------------------------------------------------------------------
# Tool implementations — each returns a result dict describing the real action.
# ----------------------------------------------------------------------------

def notes_create_from_image(args: dict) -> dict:
    """Open Apple Notes and create a new note from extracted image text."""
    title = str(args.get("title") or "Felix Note").strip()
    content = str(args.get("content") or "").strip()
    if not content:
        content = "(No text could be extracted from the image.)"

    # Notes treats <div>/<br> as line breaks in the body.
    body_html = content.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    body_html = body_html.replace("\n", "<br>")
    full_body = f"<div><b>{_as_escape(title)}</b></div><div>{_as_escape(body_html)}</div>"

    # Return the new note's id so it can be deleted later (Phase 2 undo).
    script = (
        'tell application "Notes"\n'
        "    activate\n"
        f'    set newNote to make new note with properties {{body:"{full_body}"}}\n'
        "    return id of newNote\n"
        "end tell"
    )
    note_id = _osascript(script)
    return {
        "tool": "notes.create_from_image",
        "status": "success",
        "message": f'Created a new note "{title}" in Apple Notes.',
        "title": title,
        "detail": content,
        "speak": f"Created a new note called {title}.",
        "data": {"note_id": note_id, "title": title},
    }


# Generic "just play something" phrases that should resume playback rather than
# search for a specific track.
_SPOTIFY_GENERIC = {
    "", "play something", "something", "anything", "music", "some music",
    "play music", "play", "resume", "shuffle", "play anything",
}


def media_play_pause(args: dict) -> dict:
    """Toggle play/pause for whatever is playing (system media key, Phase 6).

    Requires macOS Accessibility permission to send media keys.
    """
    # key code 100 = F8 = system play/pause media key.
    _osascript('tell application "System Events" to key code 100')
    return {
        "tool": "media.play_pause",
        "status": "success",
        "message": "Toggled play/pause.",
        "title": "Playback",
        "speak": "Toggled playback.",
        "data": {},
    }


def media_next_track(args: dict) -> dict:
    """Skip to the next track (system media key, Phase 6)."""
    # key code 101 = F9 = system next-track media key.
    _osascript('tell application "System Events" to key code 101')
    return {
        "tool": "media.next_track",
        "status": "success",
        "message": "Skipped to the next track.",
        "title": "Next Track",
        "speak": "Skipping to next track.",
        "data": {},
    }


def media_previous_track(args: dict) -> dict:
    """Go back to the previous track (system media key, Phase 6)."""
    # key code 98 = F7 = system previous-track media key.
    _osascript('tell application "System Events" to key code 98')
    return {
        "tool": "media.previous_track",
        "status": "success",
        "message": "Went back to the previous track.",
        "title": "Previous Track",
        "speak": "Going back.",
        "data": {},
    }


def media_open_spotify(args: dict) -> dict:
    """Open Spotify (optionally to a search) and start playback (Phase 6).

    Flow: ``open spotify:`` (or ``spotify:search:{query}``), wait 1.5s for the
    UI, then send the play media key. Never UI-scripts or polls for buttons.
    Requires Accessibility permission to send the media key.
    """
    query = str(args.get("query") or args.get("song") or "").strip()
    specific = query.lower() not in _SPOTIFY_GENERIC

    if specific:
        uri = "spotify:search:" + urllib.parse.quote(query)
    else:
        uri = "spotify:"
    subprocess.run(["open", uri], check=True)
    time.sleep(1.5)
    # key code 100 = play/pause media key — starts the focused track.
    _osascript('tell application "System Events" to key code 100')

    speak = f"Opening Spotify and playing {query}." if specific else "Opening Spotify."
    return {
        "tool": "media.open_spotify",
        "status": "success",
        "message": (
            f'Opened Spotify to "{query}" and started playback.'
            if specific else "Opened Spotify and resumed playback."
        ),
        "title": query or "Spotify",
        "detail": uri,
        "speak": speak,
        "data": {"query": query, "uri": uri, "specific": specific},
    }


def media_open_apple_music(args: dict) -> dict:
    """Open Apple Music and optionally search for a query (Phase 6).

    Uses AppleScript to activate Music; if a query is given it plays the first
    matching track in the local library, otherwise just brings Music forward.
    """
    query = str(args.get("query") or args.get("song") or "").strip()
    if query:
        q = _as_escape(query)
        script = (
            'tell application "Music"\n'
            "    activate\n"
            "    try\n"
            f'        set results to (every track whose name contains "{q}")\n'
            "        if (count of results) > 0 then play (item 1 of results)\n"
            "    end try\n"
            "end tell"
        )
    else:
        script = 'tell application "Music" to activate'
    _osascript(script)
    return {
        "tool": "media.open_apple_music",
        "status": "success",
        "message": (
            f'Opened Apple Music and tried to play "{query}".'
            if query else "Opened Apple Music."
        ),
        "title": query or "Apple Music",
        "speak": (
            f"Opening Apple Music and playing {query}." if query
            else "Opening Apple Music."
        ),
        "data": {"query": query},
    }


def gmail_draft_email(args: dict) -> dict:
    """Open a pre-filled Gmail compose window in Chrome (does not send)."""
    to = str(args.get("to") or "").strip()
    subject = str(args.get("subject") or "").strip()
    body = str(args.get("body") or "").strip()

    params = {"view": "cm", "fs": "1"}
    if to:
        params["to"] = to
    if subject:
        params["su"] = subject
    if body:
        params["body"] = body

    compose_url = "https://mail.google.com/mail/?" + urllib.parse.urlencode(params)
    subprocess.run(["open", "-a", CHROME, compose_url], check=True)
    return {
        "tool": "gmail.draft_email",
        "status": "success",
        "message": f'Opened a Gmail draft to "{to or "(no recipient)"}" in Chrome. Not sent.',
        "title": subject or "New Draft",
        "detail": f"To: {to}\nSubject: {subject}\n\n{body}",
        "url": compose_url,
        "data": {"to": to, "subject": subject, "compose_url": compose_url},
    }


# Control-character delimiters for parsing Mail.app AppleScript output. Email
# bodies are full of tabs/newlines, so we separate fields with ASCII RS (30) and
# records with ASCII GS (29), which never appear in message text (Phase 2).
_MAIL_FIELD = chr(30)
_MAIL_RECORD = chr(29)
_MAIL_NOTFOUND = "<<FELIX_NOTFOUND>>"


def _parse_mail_records(raw: str) -> list:
    """Parse RS/GS-delimited Mail output into [{sender, subject, date, content}]."""
    messages = []
    for rec in raw.split(_MAIL_RECORD):
        if not rec.strip():
            continue
        fields = rec.split(_MAIL_FIELD)
        fields += [""] * (4 - len(fields))
        sender, subject, date, content = (f.strip() for f in fields[:4])
        messages.append({
            "sender": sender,
            "subject": subject,
            "date": date,
            "content": content,
            "preview": " ".join(content.split())[:200],
        })
    return messages


def gmail_read_inbox(args: dict) -> dict:
    """Read the most recent inbox messages from Mail.app.

    Requires Mail.app to be configured and Automation permission to control it.
    Returns sender, subject, date, and a 200-char preview per message.
    """
    count = _clamp(args.get("count") or 10, 1, 50)
    script = (
        "set fieldD to (character id 30)\n"
        "set recD to (character id 29)\n"
        'set output to ""\n'
        'tell application "Mail"\n'
        "    set theMessages to messages of inbox\n"
        "    set n to count of theMessages\n"
        f"    if n > {count} then set n to {count}\n"
        "    repeat with i from 1 to n\n"
        "        set m to item i of theMessages\n"
        '        set theSender to ""\n        set theSubject to ""\n'
        '        set theDate to ""\n        set theContent to ""\n'
        "        try\n            set theSender to sender of m\n        end try\n"
        "        try\n            set theSubject to subject of m\n        end try\n"
        "        try\n            set theDate to (date received of m) as string\n        end try\n"
        "        try\n            set theContent to content of m\n        end try\n"
        "        set output to output & theSender & fieldD & theSubject & fieldD "
        "& theDate & fieldD & theContent & recD\n"
        "    end repeat\n"
        "end tell\n"
        "return output"
    )
    messages = _parse_mail_records(_osascript(script, timeout=45.0))

    if messages:
        latest = messages[0]
        speak = (
            f"You have {len(messages)} email{'s' if len(messages) != 1 else ''} "
            f"in your inbox. The latest is from {latest['sender']} about "
            f"{latest['subject']}."
        )
        blocks = [
            f"From: {m['sender']}\n{m['subject']}  ({m['date']})\n{m['preview']}"
            for m in messages
        ]
        summary = (
            f"Inbox — {len(messages)} email{'s' if len(messages) != 1 else ''}\n\n"
            + f"\n{'—' * 24}\n".join(blocks)
        )
    else:
        speak = "Your inbox is empty."
        summary = "No messages in your inbox."

    return {
        "tool": "gmail.read_inbox",
        "status": "success",
        "message": f"Read {len(messages)} inbox message(s) from Mail.",
        "title": "Inbox",
        "detail": "\n".join(f"{m['sender']} — {m['subject']}" for m in messages),
        "speak": speak,
        "summary": summary,
        "data": {"messages": messages},
    }


def gmail_read_email(args: dict) -> dict:
    """Read the full content of the first inbox message whose subject matches.

    Requires Mail.app and Automation permission.
    """
    query = str(args.get("subject_query") or args.get("query") or "").strip()
    if not query:
        raise ToolError("gmail.read_email requires a 'subject_query'.")
    script = (
        "set fieldD to (character id 30)\n"
        'set output to ""\n'
        'tell application "Mail"\n'
        f'    set matchMsgs to (messages of inbox whose subject contains "{_as_escape(query)}")\n'
        "    if (count of matchMsgs) is 0 then\n"
        f'        return "{_MAIL_NOTFOUND}"\n'
        "    end if\n"
        "    set m to item 1 of matchMsgs\n"
        '    set theSender to ""\n    set theSubject to ""\n'
        '    set theDate to ""\n    set theContent to ""\n'
        "    try\n        set theSender to sender of m\n    end try\n"
        "    try\n        set theSubject to subject of m\n    end try\n"
        "    try\n        set theDate to (date received of m) as string\n    end try\n"
        "    try\n        set theContent to content of m\n    end try\n"
        "    set output to theSender & fieldD & theSubject & fieldD & theDate "
        "& fieldD & theContent\n"
        "end tell\n"
        "return output"
    )
    raw = _osascript(script, timeout=45.0)
    if raw.strip() == _MAIL_NOTFOUND:
        return {
            "tool": "gmail.read_email",
            "status": "error",
            "message": f'No inbox email found with a subject containing "{query}".',
            "title": "Email Not Found",
            "speak": f"I couldn't find an email about {query} in your inbox.",
            "data": {"subject_query": query},
        }
    msg = _parse_mail_records(raw + _MAIL_RECORD)[0]
    speak = f"This email is from {msg['sender']} about {msg['subject']}."
    summary = (
        f"From: {msg['sender']}\nSubject: {msg['subject']}\nDate: {msg['date']}\n\n"
        f"{msg['content']}"
    )
    return {
        "tool": "gmail.read_email",
        "status": "success",
        "message": f'Opened email "{msg["subject"]}" from {msg["sender"]}.',
        "title": msg["subject"] or "Email",
        "detail": summary,
        "speak": speak,
        "summary": summary,
        "data": {"message": msg},
    }


def gmail_reply_draft(args: dict) -> dict:
    """Open a pre-filled reply window in Mail.app for the first matching email.

    Does NOT send — the user reviews and sends. IRREVERSIBLE (creates a draft).
    Requires Mail.app and Automation permission.
    """
    query = str(args.get("subject_query") or args.get("query") or "").strip()
    reply_body = str(args.get("reply_body") or "").strip()
    if not query:
        raise ToolError("gmail.reply_draft requires a 'subject_query'.")
    if not reply_body:
        raise ToolError("gmail.reply_draft requires a 'reply_body'.")
    script = (
        "set fieldD to (character id 30)\n"
        'set output to ""\n'
        'tell application "Mail"\n'
        f'    set matchMsgs to (messages of inbox whose subject contains "{_as_escape(query)}")\n'
        "    if (count of matchMsgs) is 0 then\n"
        f'        return "{_MAIL_NOTFOUND}"\n'
        "    end if\n"
        "    set m to item 1 of matchMsgs\n"
        '    set theSender to ""\n    set theSubject to ""\n'
        "    try\n        set theSender to sender of m\n    end try\n"
        "    try\n        set theSubject to subject of m\n    end try\n"
        "    set theReply to reply m opening window true\n"
        "    delay 0.3\n"
        f'    set content of theReply to "{_as_escape(reply_body)}" & return & return & (content of theReply)\n'
        "    activate\n"
        "    set output to theSender & fieldD & theSubject\n"
        "end tell\n"
        "return output"
    )
    raw = _osascript(script, timeout=45.0)
    if raw.strip() == _MAIL_NOTFOUND:
        return {
            "tool": "gmail.reply_draft",
            "status": "error",
            "message": f'No inbox email found with a subject containing "{query}".',
            "title": "Email Not Found",
            "speak": f"I couldn't find an email about {query} to reply to.",
            "data": {"subject_query": query},
        }
    parts = raw.split(_MAIL_FIELD)
    parts += [""] * (2 - len(parts))
    sender, subject = parts[0].strip(), parts[1].strip()
    return {
        "tool": "gmail.reply_draft",
        "status": "success",
        "message": f'Drafted a reply to {sender or "the sender"}. Review before sending.',
        "title": "Reply Drafted",
        "detail": f"To: {sender}\nSubject: {subject}\n\n{reply_body}",
        "speak": "I've drafted a reply. Review it before sending.",
        "summary": f"To: {sender}\nSubject: {subject}\n\n{reply_body}",
        "data": {"sender": sender, "subject": subject, "reply_body": reply_body},
    }


def browser_open_url(args: dict) -> dict:
    """Open Chrome and navigate to the given URL."""
    url = str(args.get("url") or "").strip()
    if not url:
        raise ToolError("browser.open_url requires a 'url'.")
    if not url.startswith(("http://", "https://")):
        # Treat bare terms as a Google search; pass through anything domain-like.
        if "." in url and " " not in url:
            url = "https://" + url
        else:
            url = "https://www.google.com/search?q=" + urllib.parse.quote(url)

    subprocess.run(["open", "-a", CHROME, url], check=True)
    return {
        "tool": "browser.open_url",
        "status": "success",
        "message": f"Opened {url} in Chrome.",
        "title": url,
        "detail": url,
        "url": url,
        "data": {"url": url},
    }


def browser_read_page(args: dict) -> dict:
    """Read the frontmost Chrome tab: its URL/title (AppleScript) + clean text.

    Gets the active tab's URL via AppleScript, then re-fetches it with
    requests/BeautifulSoup (reusing web.fetch_page) to extract clean body text.
    Requires Automation permission to control Chrome (Phase 3).
    """
    script = (
        'tell application "Google Chrome"\n'
        "    set theURL to URL of active tab of front window\n"
        "    set theTitle to title of active tab of front window\n"
        "    return theURL & (character id 9) & theTitle\n"
        "end tell"
    )
    raw = _osascript(script, timeout=20.0)
    parts = raw.split("\t")
    url = parts[0].strip()
    page_title = parts[1].strip() if len(parts) > 1 else ""
    if not url:
        raise ToolError("Could not read the active Chrome tab. Is Chrome open?")

    try:
        fetched = web_fetch_page({"url": url})
        text = fetched["data"].get("text", "")
        page_title = page_title or fetched.get("title") or url
    except Exception as exc:  # noqa: BLE001 - login/JS-gated pages still report URL
        text = f"(Could not fetch page text: {exc})"

    summary = f"{page_title}\n{url}\n\n{text}"
    return {
        "tool": "browser.read_page",
        "status": "success",
        "message": f"Read the current Chrome tab: {page_title or url}.",
        "title": page_title or "Current Page",
        "detail": text[:3000],
        "speak": f"You're on {page_title or url}.",
        "summary": summary,
        "data": {"url": url, "title": page_title, "text": text},
    }


def browser_fill_form(args: dict) -> dict:
    """Fill fields in the frontmost Chrome tab via injected JavaScript.

    Sets each field's value by CSS selector and dispatches input + change events
    so the page's reactive framework registers the change. Does NOT submit.
    IRREVERSIBLE (mutates page state). Requires Chrome's "Allow JavaScript from
    Apple Events" (View > Developer) and Automation permission (Phase 3).
    """
    fields = args.get("fields") or []
    if not isinstance(fields, list) or not fields:
        raise ToolError("browser.fill_form requires a non-empty 'fields' list.")
    clean = [
        {"selector": str(f["selector"]), "value": str(f.get("value", ""))}
        for f in fields
        if isinstance(f, dict) and f.get("selector")
    ]
    if not clean:
        raise ToolError("browser.fill_form requires fields with a 'selector'.")

    js = (
        "(function(){var fields=" + json.dumps(clean) + ";var n=0;"
        "fields.forEach(function(f){var el=document.querySelector(f.selector);"
        "if(el){el.value=f.value;"
        "el.dispatchEvent(new Event('input',{bubbles:true}));"
        "el.dispatchEvent(new Event('change',{bubbles:true}));n++;}});"
        "return n;})();"
    )
    script = (
        'tell application "Google Chrome"\n'
        f'    set n to execute active tab of front window javascript "{_as_escape(js)}"\n'
        "    return n as string\n"
        "end tell"
    )
    raw = _osascript(script, timeout=20.0)
    try:
        filled = int(float(raw.strip()))
    except (ValueError, TypeError):
        filled = 0

    summary = "Filled fields:\n" + "\n".join(
        f"• {f['selector']} = {f['value']}" for f in clean
    )
    return {
        "tool": "browser.fill_form",
        "status": "success",
        "message": f"Filled {filled} of {len(clean)} field(s) in the current Chrome tab.",
        "title": "Form Filled",
        "detail": summary,
        "speak": f"I filled {filled} field{'s' if filled != 1 else ''}. Review before submitting.",
        "summary": summary,
        "data": {"filled": filled, "requested": len(clean), "fields": clean},
    }


def slides_create_presentation(args: dict) -> dict:
    """Create a real Google Slides deck, fill it, and open it in Chrome.

    args:
      title:  presentation title
      slides: [{ "title": str, "bullets": [str, ...] }, ...]
    """
    import google_svc

    title = str(args.get("title") or "Untitled Presentation").strip()
    slides = args.get("slides") or []
    if not isinstance(slides, list) or not slides:
        slides = [{"title": title, "bullets": []}]

    svc = google_svc.slides_service()
    pres = svc.presentations().create(body={"title": title}).execute()
    pid = pres["presentationId"]
    original_slide_ids = [s["objectId"] for s in pres.get("slides", [])]

    requests = []
    for i, slide in enumerate(slides):
        if not isinstance(slide, dict):
            slide = {"title": str(slide), "bullets": []}
        slide_id, title_id, body_id = f"s_{i}", f"t_{i}", f"b_{i}"
        s_title = str(slide.get("title") or "").strip()
        bullets = slide.get("bullets") or []
        if isinstance(bullets, str):
            bullets = [bullets]
        body_text = "\n".join(str(b).strip() for b in bullets if str(b).strip())

        requests.append({
            "createSlide": {
                "objectId": slide_id,
                "slideLayoutReference": {"predefinedLayout": "TITLE_AND_BODY"},
                "placeholderIdMappings": [
                    {"layoutPlaceholder": {"type": "TITLE", "index": 0}, "objectId": title_id},
                    {"layoutPlaceholder": {"type": "BODY", "index": 0}, "objectId": body_id},
                ],
            }
        })
        if s_title:
            requests.append({"insertText": {"objectId": title_id, "text": s_title}})
        if body_text:
            requests.append({"insertText": {"objectId": body_id, "text": body_text}})

    # Remove the default blank slide(s) so only our content remains.
    for sid in original_slide_ids:
        requests.append({"deleteObject": {"objectId": sid}})

    svc.presentations().batchUpdate(
        presentationId=pid, body={"requests": requests}
    ).execute()

    url = f"https://docs.google.com/presentation/d/{pid}/edit"
    subprocess.run(["open", "-a", CHROME, url], check=True)
    return {
        "tool": "slides.create_presentation",
        "status": "success",
        "message": f'Created a {len(slides)}-slide Google Slides deck "{title}".',
        "title": title,
        "detail": "\n\n".join(
            f"Slide {i + 1}: {s.get('title', '') if isinstance(s, dict) else s}"
            for i, s in enumerate(slides)
        ),
        "url": url,
        "data": {"presentation_id": pid, "url": url, "slide_count": len(slides)},
    }


def _normalize_rows(headers, rows):
    """Build a list-of-lists-of-strings matrix from headers + rows."""
    if not isinstance(headers, list):
        headers = []
    if not isinstance(rows, list):
        rows = []

    def _row(r):
        if isinstance(r, list):
            return [str(c) for c in r]
        if isinstance(r, dict):
            return [str(v) for v in r.values()]
        return [str(r)]

    return ([[str(h) for h in headers]] if headers else []) + [_row(r) for r in rows]


def _numbers_fill_lines(values, row_offset=0):
    """AppleScript lines that write `values` into a table, 1-indexed cells.

    row_offset shifts where writing begins (used when appending).
    """
    lines = []
    for r, row in enumerate(values, start=1 + row_offset):
        for c, val in enumerate(row, start=1):
            lines.append(
                f'set value of cell {c} of row {r} to "{_as_escape(str(val))}"'
            )
    return "\n".join(lines)


def numbers_create_spreadsheet(args: dict) -> dict:
    """Create a new Apple Numbers spreadsheet and fill it with the content."""
    title = str(args.get("title") or "Untitled Spreadsheet").strip()
    values = _normalize_rows(args.get("headers") or [], args.get("rows") or [])
    if not values:
        values = [[title]]

    ncols = max((len(r) for r in values), default=1)
    nrows = len(values)
    # Numbers rejects row/column counts below 2 (header row/column minimum).
    ncols = max(ncols, 2)
    nrows = max(nrows, 2)
    fill = _numbers_fill_lines(values)

    script = (
        'tell application "Numbers"\n'
        "    activate\n"
        "    set doc to make new document\n"
        "    tell table 1 of sheet 1 of doc\n"
        f"        set column count to {ncols}\n"
        f"        set row count to {nrows}\n"
        f"        {fill}\n"
        "    end tell\n"
        "end tell"
    )
    _osascript(script)
    return {
        "tool": "numbers.create_spreadsheet",
        "status": "success",
        "message": f'Created an Apple Numbers spreadsheet "{title}" with {nrows} row(s).',
        "title": title,
        "detail": "\n".join(", ".join(v) for v in values[:10]),
        "data": {"title": title, "rows": nrows, "cols": ncols},
    }


def numbers_add_expense(args: dict) -> dict:
    """Append a receipt to one persistent Apple Numbers expense file.

    Creates the file (with headers) on first use, then appends a row each time.

    args (either form):
      rows:     [[date, merchant, category, amount, notes], ...]
      expenses: [{ "date","merchant","category","amount","notes" }, ...]
    """
    def _from_dict(d):
        return [
            str(d.get("date", "")),
            str(d.get("merchant", d.get("vendor", d.get("store", "")))),
            str(d.get("category", "")),
            str(d.get("amount", d.get("total", d.get("price", "")))),
            str(d.get("notes", d.get("note", d.get("items", "")))),
        ]

    rows = []
    for r in (args.get("rows") or []):
        if isinstance(r, dict):
            rows.append(_from_dict(r))
        elif isinstance(r, list):
            rows.append([str(c) for c in r])
        else:
            rows.append([str(r)])
    for e in (args.get("expenses") or []):
        if isinstance(e, dict):
            rows.append(_from_dict(e))
    if not rows and any(k in args for k in ("merchant", "amount", "total", "vendor")):
        rows.append(_from_dict(args))

    if not rows:
        raise ToolError("numbers.add_expense received no expense data to append.")

    # Pad/trim each row to the 5 expense columns.
    ncols = len(EXPENSE_HEADERS)
    rows = [(r + [""] * ncols)[:ncols] for r in rows]
    path_as = _as_escape(EXPENSE_FILE)

    if os.path.exists(EXPENSE_FILE):
        # Open the existing file and append new rows after the current last row.
        append_lines = []
        for k, row in enumerate(rows, start=1):
            for c, val in enumerate(row, start=1):
                append_lines.append(
                    f'set value of cell {c} of row (startRow + {k}) to "{_as_escape(str(val))}"'
                )
        body = "\n".join(append_lines)
        script = (
            'tell application "Numbers"\n'
            "    activate\n"
            f'    set doc to open POSIX file "{path_as}"\n'
            "    tell table 1 of sheet 1 of doc\n"
            "        set startRow to row count\n"
            f"        set row count to startRow + {len(rows)}\n"
            f"        {body}\n"
            "    end tell\n"
            "    save doc\n"
            "end tell"
        )
        verb = "Added"
    else:
        # Create the file with a header row + the expense row(s), then save.
        values = [EXPENSE_HEADERS] + rows
        fill = _numbers_fill_lines(values)
        table_rows = max(len(values), 2)
        script = (
            'tell application "Numbers"\n'
            "    activate\n"
            "    set doc to make new document\n"
            "    tell table 1 of sheet 1 of doc\n"
            f"        set column count to {max(ncols, 2)}\n"
            f"        set row count to {table_rows}\n"
            f"        {fill}\n"
            "    end tell\n"
            f'    save doc in POSIX file "{path_as}"\n'
            "end tell"
        )
        verb = "Created expense file and added"

    _osascript(script)
    return {
        "tool": "numbers.add_expense",
        "status": "success",
        "message": f"{verb} {len(rows)} expense row(s) to your Felix Expenses (Numbers).",
        "title": "Felix Expenses",
        "detail": "\n".join(", ".join(r) for r in rows),
        "data": {"file": EXPENSE_FILE, "rows_added": len(rows)},
    }


def _notes_html(text: str) -> str:
    """Escape user text for an Apple Notes HTML body (newlines -> <br>)."""
    html = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return html.replace("\n", "<br>")


def notes_append_to_note(args: dict) -> dict:
    """Append content to the first Notes.app note whose name matches, else create.

    Requires Automation permission to control Notes (Phase 4).
    """
    title = str(args.get("title") or "").strip()
    content = str(args.get("content") or "").strip()
    if not title:
        raise ToolError("notes.append_to_note requires a 'title'.")
    if not content:
        raise ToolError("notes.append_to_note requires 'content' to append.")

    content_html = _as_escape(_notes_html(content))
    new_body = f'<div><b>{_as_escape(_notes_html(title))}</b></div><div>{content_html}</div>'
    script = (
        'tell application "Notes"\n'
        "    activate\n"
        f'    set matchNotes to (notes whose name contains "{_as_escape(title)}")\n'
        "    if (count of matchNotes) is 0 then\n"
        f'        set theNote to make new note with properties {{body:"{new_body}"}}\n'
        '        return "CREATED" & (character id 9) & (id of theNote)\n'
        "    else\n"
        "        set theNote to item 1 of matchNotes\n"
        f'        set body of theNote to (body of theNote) & "<div>{content_html}</div>"\n'
        '        return "APPENDED" & (character id 9) & (id of theNote)\n'
        "    end if\n"
        "end tell"
    )
    raw = _osascript(script)
    parts = raw.split("\t")
    action = parts[0].strip() if parts else "APPENDED"
    note_id = parts[1].strip() if len(parts) > 1 else None
    created = action == "CREATED"
    return {
        "tool": "notes.append_to_note",
        "status": "success",
        "message": (
            f'Created a new note "{title}".' if created
            else f'Appended to note "{title}".'
        ),
        "title": title,
        "detail": content,
        "speak": (
            f"Created a new note called {title}." if created
            else f"Added that to your note {title}."
        ),
        "data": {"title": title, "note_id": note_id, "created": created},
    }


def notes_list_notes(args: dict) -> dict:
    """List recent Notes.app notes with name and modification date (Phase 4)."""
    count = _clamp(args.get("count") or 10, 1, 50)
    script = (
        'set output to ""\n'
        'tell application "Notes"\n'
        "    set theNotes to notes\n"
        "    set n to count of theNotes\n"
        f"    if n > {count} then set n to {count}\n"
        "    repeat with i from 1 to n\n"
        "        set nt to item i of theNotes\n"
        "        set output to output & (name of nt) & (character id 9) & "
        "((modification date of nt) as string) & (character id 10)\n"
        "    end repeat\n"
        "end tell\n"
        "return output"
    )
    raw = _osascript(script, timeout=30.0)
    notes = []
    for line in raw.split("\n"):
        if not line.strip():
            continue
        parts = line.split("\t")
        parts += [""] * (2 - len(parts))
        notes.append({"name": parts[0].strip(), "modified": parts[1].strip()})

    if notes:
        speak = (
            f"You have {len(notes)} note{'s' if len(notes) != 1 else ''}. "
            f"The most recent is {notes[0]['name']}."
        )
        summary = (
            f"Notes — {len(notes)}\n\n"
            + "\n".join(f"• {n['name']}  ({n['modified']})" for n in notes)
        )
    else:
        speak = "You don't have any notes."
        summary = "No notes found."
    return {
        "tool": "notes.list_notes",
        "status": "success",
        "message": f"Listed {len(notes)} note(s) from Apple Notes.",
        "title": "Notes",
        "detail": "\n".join(n["name"] for n in notes),
        "speak": speak,
        "summary": summary,
        "data": {"notes": notes},
    }


def numbers_read_sheet(args: dict) -> dict:
    """Read up to 20 rows of the first table of the frontmost Numbers document.

    If `file_path` is given it is expanded and opened first. Requires Automation
    permission to control Numbers (Phase 4).
    """
    file_path = str(args.get("file_path") or "").strip()
    open_line = ""
    if file_path:
        resolved = os.path.abspath(os.path.expanduser(file_path))
        open_line = f'    set doc to open POSIX file "{_as_escape(resolved)}"\n'
    else:
        open_line = "    set doc to front document\n"

    script = (
        'set output to ""\n'
        'tell application "Numbers"\n'
        "    activate\n"
        + open_line
        + "    tell table 1 of sheet 1 of doc\n"
        "        set totalRows to row count\n"
        "        set cc to column count\n"
        "        set rc to totalRows\n"
        "        if rc > 20 then set rc to 20\n"
        "        set output to (totalRows as string) & (character id 10)\n"
        "        repeat with r from 1 to rc\n"
        '            set rowText to ""\n'
        "            repeat with c from 1 to cc\n"
        '                set cv to ""\n'
        "                try\n"
        "                    set cv to (value of cell c of row r) as string\n"
        "                end try\n"
        "                if c is 1 then\n"
        "                    set rowText to cv\n"
        "                else\n"
        "                    set rowText to rowText & (character id 9) & cv\n"
        "                end if\n"
        "            end repeat\n"
        "            set output to output & rowText & (character id 10)\n"
        "        end repeat\n"
        "    end tell\n"
        "end tell\n"
        "return output"
    )
    raw = _osascript(script, timeout=45.0)
    lines = [ln for ln in raw.split("\n") if ln != ""]
    if not lines:
        raise ToolError("Could not read a Numbers spreadsheet. Is one open?")
    try:
        total_rows = int(lines[0].strip())
    except (ValueError, IndexError):
        total_rows = len(lines) - 1
    rows = [ln.split("\t") for ln in lines[1:]]

    table_text = "\n".join(" | ".join(cell for cell in row) for row in rows)
    speak = (
        f"Your spreadsheet has {total_rows} row{'s' if total_rows != 1 else ''}."
    )
    summary = f"Spreadsheet — {total_rows} rows\n\n{table_text}"
    return {
        "tool": "numbers.read_sheet",
        "status": "success",
        "message": f"Read {len(rows)} of {total_rows} row(s) from the spreadsheet.",
        "title": "Spreadsheet",
        "detail": table_text,
        "speak": speak,
        "summary": summary,
        "data": {"total_rows": total_rows, "rows": rows},
    }


def numbers_edit_cell(args: dict) -> dict:
    """Set one cell in the frontmost Numbers document's first table (Phase 4)."""
    row = _clamp(args.get("row") or 0, 1, 100000)
    column = _clamp(args.get("column") or 0, 1, 1000)
    value = str(args.get("value") or "")
    script = (
        'tell application "Numbers"\n'
        "    activate\n"
        "    set doc to front document\n"
        "    tell table 1 of sheet 1 of doc\n"
        f'        set value of cell {column} of row {row} to "{_as_escape(value)}"\n'
        "    end tell\n"
        "    save doc\n"
        "end tell"
    )
    _osascript(script, timeout=30.0)
    return {
        "tool": "numbers.edit_cell",
        "status": "success",
        "message": f'Set row {row}, column {column} to "{value}".',
        "title": "Cell Updated",
        "detail": f"row {row}, column {column} = {value}",
        "speak": f"Updated row {row}, column {column} to {value}.",
        "data": {"row": row, "column": column, "value": value},
    }


# ----------------------------------------------------------------------------
# System control tools (Phase 1b)
#
# Each drives a real macOS setting via osascript or a shell utility. AppleScript
# that touches System Events / Control Center requires the host process to hold
# Accessibility permission (System Settings -> Privacy & Security -> Accessibility).
# ----------------------------------------------------------------------------

def system_set_volume(args: dict) -> dict:
    """Set the system output volume (0-100)."""
    level = _clamp(args.get("level"), 0, 100)
    _osascript(f"set volume output volume {level}")
    return {
        "tool": "system.set_volume",
        "status": "success",
        "message": f"Set system volume to {level}%.",
        "title": f"Volume {level}%",
        "data": {"level": level},
    }


def system_set_brightness(args: dict) -> dict:
    """Set display brightness (0-100).

    Uses the `brightness` CLI if installed (Homebrew). Falls back to stepping the
    brightness media keys via System Events (requires Accessibility permission):
    floor to minimum, then step up to the requested level over the ~16-notch range.
    """
    level = _clamp(args.get("level"), 0, 100)
    if shutil.which("brightness"):
        _shell(["brightness", f"{level / 100:.2f}"])
        method = "brightness CLI"
    else:
        # key code 145 = brightness down (F1), 144 = brightness up (F2).
        notches = round(level / 100 * 16)
        downs = "\n".join(["key code 145"] * 16)
        ups = "\n".join(["key code 144"] * notches)
        _osascript(
            'tell application "System Events"\n'
            f"{downs}\n{ups}\n"
            "end tell"
        )
        method = "System Events keys"
    return {
        "tool": "system.set_brightness",
        "status": "success",
        "message": f"Set display brightness to {level}% ({method}).",
        "title": f"Brightness {level}%",
        "data": {"level": level, "method": method},
    }


def _macos_major() -> int:
    """Return the macOS major version (e.g. 14), or 0 if undeterminable."""
    import platform

    try:
        return int(platform.mac_ver()[0].split(".")[0])
    except (ValueError, IndexError):
        return 0


def system_open_focus_settings(args: dict) -> dict:
    """Open System Settings to the Focus/Notifications pane (Hotfix 2).

    Modern macOS has locked down programmatic Focus toggling — no AppleScript or
    Shortcuts approach works reliably across versions. Rather than fail silently
    or flash UI scripting that needs Accessibility, we just take the user
    straight to the right Settings pane so they can flip Focus themselves.
    NEVER raises — always returns a structured result.
    """
    try:
        subprocess.run(
            ["open",
             "x-apple.systempreferences:com.apple.preference.notifications"],
            timeout=5, check=True, capture_output=True,
        )
        status, message = "success", "Opened Focus settings."
    except Exception as exc:  # noqa: BLE001 - report gracefully, never crash
        logger.warning("Could not open Focus settings: %s", exc)
        status, message = (
            "error",
            "Could not open Focus settings. Open System Settings > Focus "
            "manually to change Do Not Disturb.",
        )
    return {
        "tool": "system.open_focus_settings",
        "status": status,
        "message": message,
        "title": "Focus",
        "speak": "Opening Focus settings for you." if status == "success" else
                 "I couldn't open Focus settings. Please open them manually.",
        "summary": "",
        "data": {},
    }


def system_lock_screen(args: dict) -> dict:
    """Lock the screen (Ctrl+Cmd+Q)."""
    _osascript(
        'tell application "System Events" to keystroke "q" using '
        "{control down, command down}"
    )
    return {
        "tool": "system.lock_screen",
        "status": "success",
        "message": "Locked the screen.",
        "title": "Screen locked",
        "data": {},
    }


def system_empty_trash(args: dict) -> dict:
    """Empty the Finder Trash. IRREVERSIBLE — gated by confirmation (Phase 2)."""
    _osascript('tell application "Finder" to empty trash')
    return {
        "tool": "system.empty_trash",
        "status": "success",
        "message": "Emptied the Trash.",
        "title": "Trash emptied",
        "data": {},
    }


def system_get_battery(args: dict) -> dict:
    """Return battery percentage and charging status (parses `pmset -g batt`)."""
    out = _shell(["pmset", "-g", "batt"])
    pct = None
    for token in out.replace(";", " ").split():
        if token.endswith("%"):
            try:
                pct = int(token.rstrip("%"))
            except ValueError:
                pass
            break
    lower = out.lower()
    if "ac power" in lower or "charging" in lower and "discharging" not in lower:
        status = "charging" if "discharging" not in lower else "discharging"
        if "charged" in lower:
            status = "charged"
    else:
        status = "on battery"
    pct_str = f"{pct}%" if pct is not None else "unknown"
    charging_phrase = "charging" if status in ("charging", "charged") else "not charging"
    status_label = {"charging": "Charging", "charged": "Charged",
                    "discharging": "Not Charging", "on battery": "Not Charging"}.get(
        status, status.title())
    return {
        "tool": "system.get_battery",
        "status": "success",
        "message": f"Battery is at {pct_str} ({status}).",
        "title": "Battery Status",
        "detail": out,
        "speak": f"Your battery is at {pct_str} and is {charging_phrase}.",
        "summary": f"Battery Status\n\nLevel: {pct_str}\nStatus: {status_label}",
        "data": {"percent": pct, "status": status, "raw": out},
    }


# ----------------------------------------------------------------------------
# Finder / filesystem tools (Phase 1c)
# ----------------------------------------------------------------------------

def _resolve_path(raw: str) -> str:
    """Resolve an LLM-provided path to a safe absolute path (Fix 2).

    Rules: expand ~, then a bare name (no separator) defaults under ~/Desktop,
    and everything is made absolute. The LLM is told to pass only relative paths
    or folder names; we never trust it to build absolute paths itself.
    """
    name = str(raw or "").strip()
    if not name:
        raise ToolError("A path or folder name is required.")
    if os.sep not in name and "/" not in name and not name.startswith("~"):
        name = os.path.join("~/Desktop", name)
    return os.path.abspath(os.path.expanduser(name))


def finder_open_file(args: dict) -> dict:
    """Spotlight-search for a file and open the top result."""
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("finder.open_file requires a 'query'.")
    out = _shell(["mdfind", query])
    paths = [p for p in out.splitlines() if p.strip()]
    if not paths:
        raise ToolError(f'No file found matching "{query}".')
    top = paths[0]
    subprocess.run(["open", top], check=True)
    return {
        "tool": "finder.open_file",
        "status": "success",
        "message": f"Opened {os.path.basename(top)}.",
        "title": os.path.basename(top),
        "detail": top,
        "speak": f"Opened {os.path.basename(top)} for you.",
        "data": {"path": top, "match_count": len(paths)},
    }


def finder_find_file(args: dict) -> dict:
    """Spotlight-search and return the top 5 matches WITHOUT opening them."""
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("finder.find_file requires a 'query'.")
    out = _shell(["mdfind", query])
    paths = [p for p in out.splitlines() if p.strip()][:5]
    if not paths:
        return {
            "tool": "finder.find_file",
            "status": "success",
            "message": f'No files found matching "{query}".',
            "title": query,
            "data": {"results": []},
        }
    listing = [{"name": os.path.basename(p), "path": p} for p in paths]
    return {
        "tool": "finder.find_file",
        "status": "success",
        "message": f'Found {len(listing)} file(s) matching "{query}".',
        "title": query,
        "detail": "\n".join(p["path"] for p in listing),
        "data": {"results": listing},
    }


def finder_move_file(args: dict) -> dict:
    """Move a file/folder. IRREVERSIBLE — gated by confirmation (Phase 2)."""
    source = _resolve_path(args.get("source"))
    destination = _resolve_path(args.get("destination"))
    if not source or not destination:
        raise ToolError("finder.move_file requires 'source' and 'destination'.")
    if not os.path.exists(source):
        raise ToolError(f"Source does not exist: {source}")
    _shell(["mv", source, destination])
    # Resolve where it landed (mv into a directory keeps the basename).
    final = (
        os.path.join(destination, os.path.basename(source))
        if os.path.isdir(destination) else destination
    )
    return {
        "tool": "finder.move_file",
        "status": "success",
        "message": f"Moved {os.path.basename(source)} to {destination}.",
        "title": "File moved",
        "detail": f"{source} -> {final}",
        "data": {"source": source, "destination": final},
    }


def finder_create_folder(args: dict) -> dict:
    """Create a folder (mkdir -p)."""
    path = _resolve_path(args.get("path"))
    _shell(["mkdir", "-p", path])
    return {
        "tool": "finder.create_folder",
        "status": "success",
        "message": f"Created folder {path}.",
        "title": os.path.basename(path.rstrip("/")) or path,
        "detail": path,
        "data": {"path": path},
    }


def finder_rename_file(args: dict) -> dict:
    """Rename a file in place. IRREVERSIBLE — gated by confirmation (Phase 2)."""
    path = _resolve_path(args.get("path"))
    new_name = str(args.get("new_name") or "").strip()
    if not new_name:
        raise ToolError("finder.rename_file requires 'path' and 'new_name'.")
    if not os.path.exists(path):
        raise ToolError(f"File does not exist: {path}")
    new_path = os.path.join(os.path.dirname(path), new_name)
    _shell(["mv", path, new_path])
    return {
        "tool": "finder.rename_file",
        "status": "success",
        "message": f"Renamed {os.path.basename(path)} to {new_name}.",
        "title": new_name,
        "detail": f"{path} -> {new_path}",
        "data": {"old_path": path, "new_path": new_path},
    }


def finder_show_in_finder(args: dict) -> dict:
    """Reveal a file/folder in Finder."""
    path = _resolve_path(args.get("path"))
    _osascript(
        'tell application "Finder"\n'
        f'    reveal POSIX file "{_as_escape(path)}"\n'
        "    activate\n"
        "end tell"
    )
    return {
        "tool": "finder.show_in_finder",
        "status": "success",
        "message": f"Revealed {os.path.basename(path)} in Finder.",
        "title": os.path.basename(path),
        "detail": path,
        "data": {"path": path},
    }


# ----------------------------------------------------------------------------
# Clipboard tool (Phase 1d)
# ----------------------------------------------------------------------------

def clipboard_copy_text(args: dict) -> dict:
    """Copy text to the macOS clipboard via pbcopy."""
    text = str(args.get("text") or "")
    if not text:
        raise ToolError("clipboard.copy_text requires 'text'.")
    proc = subprocess.run(["pbcopy"], input=text, text=True)
    if proc.returncode != 0:
        raise RuntimeError("pbcopy failed.")
    preview = text if len(text) <= 80 else text[:77] + "..."
    return {
        "tool": "clipboard.copy_text",
        "status": "success",
        "message": f'Copied to clipboard: "{preview}"',
        "title": "Copied",
        "detail": text,
        "speak": "Copied to your clipboard.",
        "data": {"text": text, "length": len(text)},
    }


# ----------------------------------------------------------------------------
# Calendar tools (Phase 1e)
#
# Natural-language dates ("tomorrow at 3pm") are converted to ISO8601 in llm.py
# (dateparser) BEFORE these tools run, so start_datetime is expected to be ISO.
# ----------------------------------------------------------------------------

def _parse_iso(value: str):
    """Parse an ISO8601 string into a datetime, tolerating a trailing 'Z'."""
    from datetime import datetime

    s = str(value or "").strip().replace("Z", "+00:00")
    if not s:
        raise ToolError("A start_datetime (ISO8601) is required.")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        # Last-resort: dateparser if the string is not strict ISO.
        try:
            import dateparser

            dt = dateparser.parse(s)
            if dt:
                return dt
        except Exception:  # noqa: BLE001
            pass
        raise ToolError(f"Could not parse start_datetime: {value!r}")


def _as_applescript_date(dt) -> str:
    """Build an AppleScript `date "..."` expression from a datetime.

    Uses an explicit, locale-stable construction to avoid string-format
    ambiguity across system date settings.
    """
    return (
        "(my makeDate(%d, %d, %d, %d, %d))"
        % (dt.year, dt.month, dt.day, dt.hour, dt.minute)
    )


_MAKE_DATE_HANDLER = (
    "on makeDate(y, m, d, hh, mm)\n"
    "    set theDate to current date\n"
    "    set year of theDate to y\n"
    "    set month of theDate to m\n"
    "    set day of theDate to d\n"
    "    set hours of theDate to hh\n"
    "    set minutes of theDate to mm\n"
    "    set seconds of theDate to 0\n"
    "    return theDate\n"
    "end makeDate\n"
)


def calendar_create_event(args: dict) -> dict:
    """Create a Calendar.app event. IRREVERSIBLE — gated by confirmation (Phase 2)."""
    from datetime import timedelta

    title = str(args.get("title") or "Felix Event").strip()
    start = _parse_iso(args.get("start_datetime"))
    duration = _clamp(args.get("duration_minutes") or 60, 1, 24 * 60)
    end = start + timedelta(minutes=duration)
    notes = str(args.get("notes") or "").strip()
    cal_name = str(args.get("calendar_name") or "").strip()

    cal_selector = (
        f'calendar "{_as_escape(cal_name)}"' if cal_name else "calendar 1"
    )
    script = (
        _MAKE_DATE_HANDLER
        + 'tell application "Calendar"\n'
        "    activate\n"
        f"    tell {cal_selector}\n"
        f'        set newEvent to make new event with properties {{summary:"{_as_escape(title)}", '
        f"start date:{_as_applescript_date(start)}, end date:{_as_applescript_date(end)}"
        + (f', description:"{_as_escape(notes)}"' if notes else "")
        + "}\n"
        "    end tell\n"
        "end tell"
    )
    _osascript(script)
    return {
        "tool": "calendar.create_event",
        "status": "success",
        "message": (
            f'Created "{title}" on {start.strftime("%a %b %d at %-I:%M %p")} '
            f"({duration} min)."
        ),
        "title": title,
        "detail": f"{start.isoformat()} for {duration} min"
        + (f" — {notes}" if notes else ""),
        "speak": (
            f'Done. I\'ve added {title} to your calendar on '
            f'{start.strftime("%A, %B %-d")} at {start.strftime("%-I:%M %p")}.'
        ),
        "data": {
            "title": title,
            "start": start.isoformat(),
            "end": end.isoformat(),
            "calendar_name": cal_name or None,
        },
    }


def _read_calendar_events(days: int) -> list:
    """Return events from now through `days` days ahead as dicts."""
    from datetime import datetime, timedelta

    now = datetime.now()
    end = now + timedelta(days=days)
    script = (
        _MAKE_DATE_HANDLER
        + 'set startD to %s\n' % _as_applescript_date(now)
        + 'set endD to %s\n' % _as_applescript_date(end)
        + 'set output to ""\n'
        'tell application "Calendar"\n'
        "    repeat with cal in calendars\n"
        "        set calName to name of cal\n"
        "        repeat with ev in (every event of cal whose start date is "
        "greater than or equal to startD and start date is less than or equal to endD)\n"
        '            set evLoc to ""\n'
        "            try\n"
        "                set evLoc to location of ev as string\n"
        "            end try\n"
        '            set output to output & (summary of ev) & "\\t" & '
        '((start date of ev) as string) & "\\t" & ((end date of ev) as string) & '
        '"\\t" & evLoc & "\\t" & calName & "\\n"\n'
        "        end repeat\n"
        "    end repeat\n"
        "end tell\n"
        "return output"
    )
    out = _osascript(script, timeout=45.0)
    events = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        parts += [""] * (5 - len(parts))
        events.append({
            "title": parts[0],
            "start_time": parts[1],
            "end_time": parts[2],
            "location": parts[3],
            "calendar_name": parts[4],
        })
    return events


def calendar_read_today(args: dict) -> dict:
    """Read all of today's calendar events."""
    events = [
        e for e in _read_calendar_events(1)
        # _read_calendar_events(1) covers next 24h; today's are close enough for demo.
    ]
    from datetime import datetime
    if events:
        first = events[0]
        speak = (
            f"You have {len(events)} event{'s' if len(events) != 1 else ''} today. "
            f"First up is {first['title']} at {first['start_time']}."
        )
        body = "\n".join(
            f"{e['start_time']} — {e['title']}"
            + (f" ({e['location']})" if e.get("location") else "")
            for e in events
        )
        summary = f"Today — {datetime.now().strftime('%A, %B %-d')}\n\n{body}"
    else:
        speak = "Your calendar is clear today."
        summary = "No events scheduled for today."
    return {
        "tool": "calendar.read_today",
        "status": "success",
        "message": f"You have {len(events)} event(s) coming up today.",
        "title": "Today's Calendar",
        "detail": "\n".join(f"{e['start_time']} — {e['title']}" for e in events),
        "speak": speak,
        "summary": summary,
        "data": {"events": events},
    }


def calendar_read_week(args: dict) -> dict:
    """Read calendar events for the next 7 days."""
    events = _read_calendar_events(7)
    if events:
        first = events[0]
        # AppleScript start_time looks like "Tuesday, June 24, 2026 at 3:00 PM";
        # the leading token before the comma is the weekday.
        day = first["start_time"].split(",", 1)[0] if first.get("start_time") else ""
        speak = (
            f"You have {len(events)} event{'s' if len(events) != 1 else ''} this "
            f"week. Next up is {first['title']}"
            + (f" on {day}." if day else ".")
        )
        # Group by day for the summary.
        grouped: dict = {}
        for e in events:
            d = e["start_time"].split(",", 1)[0] if e.get("start_time") else "Upcoming"
            grouped.setdefault(d, []).append(e)
        blocks = []
        for d, evs in grouped.items():
            lines = "\n".join(f"{e['start_time']} — {e['title']}" for e in evs)
            blocks.append(f"{d}\n{lines}")
        summary = "This Week\n\n" + "\n\n".join(blocks)
    else:
        speak = "You have nothing scheduled this week."
        summary = "No events scheduled this week."
    return {
        "tool": "calendar.read_week",
        "status": "success",
        "message": f"You have {len(events)} event(s) over the next 7 days.",
        "title": "This Week's Calendar",
        "detail": "\n".join(f"{e['start_time']} — {e['title']}" for e in events),
        "speak": speak,
        "summary": summary,
        "data": {"events": events},
    }


def calendar_find_free_time(args: dict) -> dict:
    """Find up to 3 free slots of `duration_minutes` within `within_days`.

    Considers work hours 9am-6pm and existing calendar events as busy blocks.
    """
    from datetime import datetime, timedelta

    duration = _clamp(args.get("duration_minutes") or 30, 5, 12 * 60)
    within = _clamp(args.get("within_days") or 7, 1, 30)
    events = _read_calendar_events(within)

    # Build busy intervals by parsing event start/end via dateparser (AppleScript
    # date strings are locale formatted, so dateparser is the safe parser here).
    import dateparser

    busy = []
    for e in events:
        s = dateparser.parse(e["start_time"])
        en = dateparser.parse(e["end_time"])
        if s and en:
            busy.append((s, en))
    busy.sort()

    slots = []
    now = datetime.now()
    for day in range(within):
        date = (now + timedelta(days=day)).date()
        cursor = datetime.combine(date, datetime.min.time()).replace(hour=9)
        if day == 0 and now > cursor:
            # Round up to the next 15 minutes today.
            cursor = now + (timedelta(minutes=15) - timedelta(
                minutes=now.minute % 15, seconds=now.second,
                microseconds=now.microsecond))
        day_end = datetime.combine(date, datetime.min.time()).replace(hour=18)
        while cursor + timedelta(minutes=duration) <= day_end:
            slot_end = cursor + timedelta(minutes=duration)
            overlap = any(s < slot_end and cursor < en for s, en in busy)
            if not overlap:
                slots.append((cursor, slot_end))
                cursor = slot_end
            else:
                cursor += timedelta(minutes=15)
            if len(slots) >= 3:
                break
        if len(slots) >= 3:
            break

    listing = [
        {
            "start": s.isoformat(),
            "end": e.isoformat(),
            "label": s.strftime("%a %b %d, %-I:%M %p"),
        }
        for s, e in slots
    ]
    return {
        "tool": "calendar.find_free_time",
        "status": "success",
        "message": (
            f"Found {len(listing)} free {duration}-minute slot(s)."
            if listing else f"No free {duration}-minute slots in the next {within} days."
        ),
        "title": "Free time",
        "detail": "\n".join(s["label"] for s in listing),
        "data": {"slots": listing},
    }


# ----------------------------------------------------------------------------
# Reminders tools (Phase 1f)
# ----------------------------------------------------------------------------

def reminders_add_item(args: dict) -> dict:
    """Add a reminder. IRREVERSIBLE — gated by confirmation (Phase 2)."""
    title = str(args.get("title") or "").strip()
    if not title:
        raise ToolError("reminders.add_item requires a 'title'.")
    list_name = str(args.get("list_name") or "Reminders").strip()
    notes = str(args.get("notes") or "").strip()
    due = args.get("due_date")

    props = [f'name:"{_as_escape(title)}"']
    if notes:
        props.append(f'body:"{_as_escape(notes)}"')
    handler = ""
    if due:
        dt = _parse_iso(due)
        handler = _MAKE_DATE_HANDLER
        props.append(f"due date:{_as_applescript_date(dt)}")
    script = (
        handler
        + 'tell application "Reminders"\n'
        f'    tell list "{_as_escape(list_name)}"\n'
        f'        make new reminder with properties {{{", ".join(props)}}}\n'
        "    end tell\n"
        "end tell"
    )
    _osascript(script)
    return {
        "tool": "reminders.add_item",
        "status": "success",
        "message": f'Added "{title}" to the {list_name} list.',
        "title": title,
        "detail": f"List: {list_name}" + (f"\n{notes}" if notes else ""),
        "speak": f"Added {title} to your reminders.",
        "data": {"title": title, "list_name": list_name},
    }


def reminders_read_list(args: dict) -> dict:
    """Read incomplete reminders from a list (default: all lists)."""
    list_name = str(args.get("list_name") or "").strip()
    if list_name:
        target = f'tell list "{_as_escape(list_name)}"'
        wrapper_open, wrapper_close = target + "\n", "end tell\n"
        loop = (
            "    repeat with r in (reminders whose completed is false)\n"
            '        set output to output & (name of r) & "\\t" & '
            '(due date of r as string) & "\\t" & (body of r as string) & "\\n"\n'
            "    end repeat\n"
        )
        body = wrapper_open + loop + wrapper_close
    else:
        body = (
            "    repeat with lst in lists\n"
            "        repeat with r in (reminders of lst whose completed is false)\n"
            '            set output to output & (name of r) & "\\t" & '
            '(due date of r as string) & "\\t" & (body of r as string) & "\\n"\n'
            "        end repeat\n"
            "    end repeat\n"
        )
    script = (
        'set output to ""\n'
        'tell application "Reminders"\n'
        + body
        + "end tell\n"
        "return output"
    )
    out = _osascript(script, timeout=45.0)
    items = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        parts += [""] * (3 - len(parts))
        items.append({
            "title": parts[0],
            "due_date": parts[1] if parts[1] != "missing value" else "",
            "notes": parts[2] if parts[2] != "missing value" else "",
        })
    if items:
        speak = (
            f"You have {len(items)} reminder{'s' if len(items) != 1 else ''}. "
            f"First is {items[0]['title']}."
        )
        lines = "\n".join(
            f"• {i['title']}" + (f" (due {i['due_date']})" if i.get("due_date") else "")
            for i in items
        )
        summary = f"Reminders — {list_name or 'All'}\n\n{lines}"
    else:
        speak = "Your reminders list is empty."
        summary = "Your reminders list is empty."
    return {
        "tool": "reminders.read_list",
        "status": "success",
        "message": f"You have {len(items)} open reminder(s)"
        + (f' in "{list_name}".' if list_name else "."),
        "title": list_name or "Reminders",
        "detail": "\n".join(i["title"] for i in items),
        "speak": speak,
        "summary": summary,
        "data": {"items": items, "list_name": list_name or None},
    }


def reminders_complete_item(args: dict) -> dict:
    """Mark the first matching incomplete reminder as complete."""
    title = str(args.get("title") or "").strip()
    if not title:
        raise ToolError("reminders.complete_item requires a 'title'.")
    list_name = str(args.get("list_name") or "").strip()
    scope = (
        f'reminders of list "{_as_escape(list_name)}"'
        if list_name else "reminders"
    )
    script = (
        'tell application "Reminders"\n'
        f'    set matches to ({scope} whose completed is false and '
        f'name contains "{_as_escape(title)}")\n'
        "    if (count matches) is 0 then return \"NONE\"\n"
        "    set completed of (item 1 of matches) to true\n"
        "    return name of (item 1 of matches)\n"
        "end tell"
    )
    result = _osascript(script)
    if result == "NONE":
        return {
            "tool": "reminders.complete_item",
            "status": "error",
            "message": f'No open reminder matching "{title}" was found.',
            "title": title,
            "data": {"matched": False},
        }
    return {
        "tool": "reminders.complete_item",
        "status": "success",
        "message": f'Completed reminder "{result}".',
        "title": result,
        "data": {"matched": True, "title": result},
    }


# ----------------------------------------------------------------------------
# Contacts tool (Phase 1g)
# ----------------------------------------------------------------------------

def _contacts_strict_search(query: str) -> list:
    """AppleScript `contains` search across name/first/last/nickname (fast path)."""
    q = _as_escape(query)
    script = (
        'set output to ""\n'
        'tell application "Contacts"\n'
        f'    set matches to (every person whose name contains "{q}" or '
        f'first name contains "{q}" or last name contains "{q}" or '
        f'nickname contains "{q}")\n'
        "    set n to count matches\n"
        "    if n > 5 then set n to 5\n"
        "    repeat with i from 1 to n\n"
        "        set p to item i of matches\n"
        '        set theEmail to ""\n'
        '        set thePhone to ""\n'
        "        try\n"
        "            set theEmail to value of email 1 of p\n"
        "        end try\n"
        "        try\n"
        "            set thePhone to value of phone 1 of p\n"
        "        end try\n"
        '        set output to output & (name of p) & "\\t" & theEmail & '
        '"\\t" & thePhone & "\\n"\n'
        "    end repeat\n"
        "end tell\n"
        "return output"
    )
    return _parse_contacts(_osascript(script))


def _contacts_all() -> list:
    """Fetch every contact's name/email/phone for in-Python fuzzy matching."""
    script = (
        'set output to ""\n'
        'tell application "Contacts"\n'
        "    repeat with p in people\n"
        '        set theEmail to ""\n'
        '        set thePhone to ""\n'
        "        try\n"
        "            set theEmail to value of email 1 of p\n"
        "        end try\n"
        "        try\n"
        "            set thePhone to value of phone 1 of p\n"
        "        end try\n"
        '        set output to output & (name of p) & "\\t" & theEmail & '
        '"\\t" & thePhone & "\\n"\n'
        "    end repeat\n"
        "end tell\n"
        "return output"
    )
    return _parse_contacts(_osascript(script, timeout=45.0))


def _parse_contacts(out: str) -> list:
    """Parse tab-separated name/email/phone lines into contact dicts."""
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        parts += [""] * (3 - len(parts))
        name = parts[0].strip()
        if name and name != "missing value":
            rows.append({"name": name,
                         "email": "" if parts[1] == "missing value" else parts[1],
                         "phone": "" if parts[2] == "missing value" else parts[2]})
    return rows


def _fuzzy_rank_contacts(query: str, people: list, limit: int = 3) -> list:
    """Score contacts against a possibly-misheard query and return the best ones.

    Speech often mangles names ("Chauhan" -> "chauhans"/"chaudhary"), so we
    combine substring, token-prefix, and difflib similarity over both the full
    name and each name token, then keep the closest matches above a threshold.
    """
    from difflib import SequenceMatcher

    q = query.lower().strip()
    scored = []
    for person in people:
        name = person["name"].lower()
        tokens = name.split()
        # Best similarity across the whole name and each individual token.
        best = SequenceMatcher(None, q, name).ratio()
        for tok in tokens:
            best = max(best, SequenceMatcher(None, q, tok).ratio())
            # Reward shared prefixes (handles trailing-character mishears).
            if tok.startswith(q[:4]) or q.startswith(tok[:4]):
                best = max(best, 0.8)
        if q and q in name:           # direct substring is a strong signal
            best = max(best, 0.9)
        if best >= 0.6:
            scored.append((best, person))
    scored.sort(key=lambda s: s[0], reverse=True)
    return [p for _, p in scored[:limit]]


def contacts_find(args: dict) -> dict:
    """Find a contact, tolerating misheard/partial names (Hotfix 2)."""
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("contacts.find requires a 'query'.")

    # 1. Fast path: AppleScript `contains` search.
    matches = _contacts_strict_search(query)[:3]

    # 2. Fuzzy fallback: pull every contact and rank by similarity in Python.
    if not matches:
        try:
            matches = _fuzzy_rank_contacts(query, _contacts_all())
        except Exception as exc:  # noqa: BLE001 - degrade to the strict result
            logger.info("Contacts fuzzy fallback failed (%s).", exc)
            matches = []

    # 3. Still nothing — return a helpful, actionable error (never silent).
    if not matches:
        short = query.split()[0] if query.split() else query
        return {
            "tool": "contacts.find",
            "status": "error",
            "message": (
                f"No contact found matching '{query}'. Try a shorter version of "
                f"the name (e.g. just \"{short[:4]}\")."
            ),
            "title": query,
            "speak": f"I couldn't find a contact matching {query}. Try a shorter name.",
            "data": {"results": []},
        }

    top = matches[0]
    summary = "Contact Found\n\n" + "\n\n".join(
        f"Name: {m['name']}\nEmail: {m['email'] or '—'}\nPhone: {m['phone'] or '—'}"
        for m in matches
    )
    return {
        "tool": "contacts.find",
        "status": "success",
        "message": f'Found {len(matches)} contact(s) matching "{query}".',
        "title": query,
        "detail": "\n".join(f"{m['name']} — {m['email']}" for m in matches),
        "speak": (
            f"Found {top['name']}. Their email is {top['email'] or 'not listed'} "
            f"and phone is {top['phone'] or 'not listed'}."
        ),
        "summary": summary,
        "data": {"results": matches},
    }


# ----------------------------------------------------------------------------
# Screen-awareness tools (Phase 1h / Phase 5)
#
# Felix "sees" the Mac screen: capture a screenshot, send it to Groq vision,
# and either describe it or build+execute a plan from what it sees.
# ----------------------------------------------------------------------------

def _capture_screen_b64() -> str:
    """Take a silent screenshot to a temp file and return it base64-encoded."""
    path = "/tmp/felix_screen.png"
    _shell(["screencapture", "-x", "-t", "png", path])
    try:
        with open(path, "rb") as fh:
            return base64.b64encode(fh.read()).decode("ascii")
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def screen_capture_and_describe(args: dict) -> dict:
    """Screenshot the Mac and return a Groq vision description of it (Fix 6)."""
    image_b64 = _capture_screen_b64()
    description = _groq_vision(
        image_b64,
        "Describe what is on this Mac screen in detail. Include: the app in "
        "focus, any visible text, any errors or warnings, and what the user "
        "appears to be working on. Be specific and thorough.",
    )
    return {
        "tool": "screen.capture_and_describe",
        "status": "success",
        "message": description[:280] + ("..." if len(description) > 280 else ""),
        "title": "Screen Description",
        "detail": description,
        "speak": _first_two_sentences(description),
        "summary": description,
        "data": {"description": description},
    }


def screen_capture_and_act(args: dict) -> dict:
    """Screenshot the Mac, ask Groq for a tool plan, then execute it (Fix 6).

    Groq returns a {"steps":[...]} plan referencing Felix's tools based on what
    it sees. Steps run synchronously through ``execute`` (this tool already runs
    inside the engine's executor, so we avoid re-entering the async engine).
    """
    import json

    instruction = str(args.get("instruction") or "").strip()
    if not instruction:
        raise ToolError("screen.capture_and_act requires an 'instruction'.")
    image_b64 = _capture_screen_b64()
    tool_list = ", ".join(sorted(TOOL_REGISTRY))
    raw = _groq_vision(
        image_b64,
        "Here is a screenshot of the user's Mac. The user wants to: "
        f"{instruction}\nBased on what you see, create a step-by-step plan using "
        f"ONLY these Felix tools: {tool_list}.\nRespond with ONLY a JSON object "
        '{"steps": [{"tool": "<tool>", "args": {...}}, ...]}. No prose.',
    )
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    try:
        plan = json.loads(raw)
        steps = plan.get("steps", []) if isinstance(plan, dict) else []
    except (json.JSONDecodeError, AttributeError):
        steps = []

    executed = []
    for step in steps:
        if not isinstance(step, dict):
            continue
        t = str(step.get("tool", "")).strip()
        if t in TOOL_REGISTRY and t not in ("screen.capture_and_act",):
            executed.append(execute(t, step.get("args") or {}))

    ok = sum(1 for r in executed if r.get("status") == "success")
    return {
        "tool": "screen.capture_and_act",
        "status": "success" if executed else "error",
        "message": (
            f"Looked at your screen and ran {ok}/{len(executed)} step(s) for: "
            f"{instruction}"
            if executed else
            f"Looked at your screen but produced no executable steps for: {instruction}"
        ),
        "title": "Screen action",
        "detail": "\n".join(
            f"{r.get('tool')}: {r.get('message')}" for r in executed
        ),
        "data": {"instruction": instruction, "steps": executed},
    }


# ----------------------------------------------------------------------------
# Web research agent (Phase 6)
#
# web.search   -> top 5 results (multi-backend, no API key)
# web.fetch_page -> clean text of a URL (requests + BeautifulSoup, <=3000 chars)
# web.research -> compound: search + fetch + Groq synthesis -> saved as a Note
# ----------------------------------------------------------------------------

def _unwrap_ddg(href: str) -> str:
    """Unwrap DuckDuckGo's /l/?uddg=<encoded-url> redirect to the real URL."""
    if "uddg=" in href:
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
        href = urllib.parse.unquote(qs.get("uddg", [href])[0])
    if href.startswith("//"):
        href = "https:" + href
    return href


def _duckduckgo_search(query: str, limit: int = 5) -> list:
    """Search via DuckDuckGo's HTML endpoint (no API key)."""
    import requests
    from bs4 import BeautifulSoup

    resp = requests.post(
        "https://html.duckduckgo.com/html/",
        data={"q": query},
        headers={"User-Agent": _WEB_UA},
        timeout=15,
    )
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    results = []
    # Markup varies; accept either the classed result block or any result link.
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
    """Search via the lightweight lite.duckduckgo.com endpoint (no API key)."""
    import requests
    from bs4 import BeautifulSoup

    resp = requests.post(
        "https://lite.duckduckgo.com/lite/",
        data={"q": query},
        headers={"User-Agent": _WEB_UA},
        timeout=15,
    )
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
    """DuckDuckGo Instant Answer JSON API — keyless, returns related topics."""
    import requests

    resp = requests.get(
        "https://api.duckduckgo.com/",
        params={"q": query, "format": "json", "no_html": 1, "skip_disambig": 1},
        headers={"User-Agent": _WEB_UA},
        timeout=15,
    )
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
        if "Topics" in topic:  # nested category
            for sub in topic["Topics"]:
                if len(results) >= limit:
                    break
                add(sub.get("Text", ""), sub.get("FirstURL", ""))
        else:
            add(topic.get("Text", ""), topic.get("FirstURL", ""))
    return results[:limit]


def _wikipedia_search(query: str, limit: int = 5) -> list:
    """Wikipedia opensearch API — extremely reliable last-resort, keyless."""
    import requests

    resp = requests.get(
        "https://en.wikipedia.org/w/api.php",
        params={"action": "opensearch", "search": query, "limit": limit,
                "namespace": 0, "format": "json"},
        headers={"User-Agent": _WEB_UA},
        timeout=15,
    )
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
    """Return up to `limit` web results, trying multiple keyless backends.

    Any single backend can transiently return nothing (markup change, rate
    limit, sparse instant-answer), so we fall through DDG HTML -> DDG Lite ->
    DDG Instant Answer -> Wikipedia until we have results (Hotfix 3).
    """
    backends = (
        _duckduckgo_search, _ddg_lite_search, _ddg_instant_answer, _wikipedia_search,
    )
    for backend in backends:
        try:
            results = backend(query, limit)
        except Exception as exc:  # noqa: BLE001 - try the next backend
            logger.info("Search backend %s failed for %r: %s",
                        backend.__name__, query, exc)
            continue
        if results:
            return results[:limit]
    return []


def web_search(args: dict) -> dict:
    """Search the web and return the top 5 results as structured data."""
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("web.search requires a 'query'.")
    try:
        results = _search_web(query, 5)
    except Exception as exc:  # noqa: BLE001 - surface a graceful error contract
        return {
            "tool": "web.search",
            "status": "error",
            "message": f'Web search failed for "{query}": {exc}',
            "title": query,
            "data": {"query": query, "results": [], "error": str(exc)},
        }
    return {
        "tool": "web.search",
        "status": "success",
        "message": f'Found {len(results)} result(s) for "{query}".',
        "title": query,
        "detail": "\n".join(f"{r['title']} — {r['url']}" for r in results),
        "data": {"query": query, "results": results},
    }


def web_fetch_page(args: dict) -> dict:
    """Fetch a URL and return its clean text, truncated to 3000 characters."""
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
    return {
        "tool": "web.fetch_page",
        "status": "success",
        "message": f"Fetched {len(truncated)} chars from {url}.",
        "title": page_title,
        "detail": truncated,
        "url": url,
        "data": {
            "url": url,
            "title": page_title,
            "text": truncated,
            "length": len(text),
            "truncated": len(text) > 3000,
        },
    }


def web_research(args: dict) -> dict:
    """Research a topic end-to-end and save the synthesis as an Apple Note.

    Runs several searches, fetches the top 3 results, asks Groq to synthesize
    the content into the requested format with citations, then creates a Note.
    """
    topic = str(args.get("topic") or args.get("query") or "").strip()
    if not topic:
        raise ToolError("web.research requires a 'topic'.")
    output_format = str(args.get("output_format") or "note").strip().lower()
    if output_format not in ("note", "document", "summary"):
        output_format = "note"

    # 1. Run 3-5 searches and collect unique sources.
    queries = [
        topic,
        f"{topic} overview",
        f"{topic} latest",
        f"{topic} explained",
    ]
    sources, seen = [], set()
    for q in queries:
        try:
            for r in _search_web(q, 5):
                u = r.get("url")
                if u and u not in seen:
                    seen.add(u)
                    sources.append(r)
        except Exception as exc:  # noqa: BLE001 - one failed query shouldn't abort
            logger.info("Research search failed for %r: %s", q, exc)
        if len(sources) >= 6:
            break

    # If every live-search backend came up empty, fall back to Groq's own
    # knowledge rather than returning nothing — clearly labelled so the user
    # knows it is not sourced from live pages (Hotfix 3).
    if not sources:
        logger.info("No live sources for %r; using Groq-knowledge fallback.", topic)
        try:
            knowledge = _groq_text(
                f"Write a {output_format} about {topic}. Be specific, accurate, "
                "and well-organized. If you are unsure about any detail, say so."
            ).strip()
        except Exception as exc:  # noqa: BLE001 - only now is it a real failure
            logger.warning("Groq-knowledge fallback failed for %r: %s", topic, exc)
            return {
                "tool": "web.research",
                "status": "error",
                "message": f'Could not find sources or generate a summary for "{topic}".',
                "title": topic,
                "speak": f"I couldn't research {topic} right now.",
                "data": {"topic": topic, "sources": []},
            }

        disclaimer = (
            "Note: This summary is from AI knowledge, not live sources. "
            "Live web search returned no results, so details may be out of date."
        )
        full_content = f"{disclaimer}\n\n{knowledge}"
        note_title = f"Research: {topic}"
        note_id = None
        try:
            note = notes_create_from_image({"title": note_title, "content": full_content})
            note_id = (note.get("data") or {}).get("note_id")
        except Exception as exc:  # noqa: BLE001 - synthesis is still useful
            logger.warning("web.research could not save the note: %s", exc)
        research_summary = knowledge[:500]
        if len(knowledge) > 500:
            research_summary += "\n\nSee note for full summary."
        research_summary = f"{disclaimer}\n\n{research_summary}"
        return {
            "tool": "web.research",
            "status": "success",
            "message": f'Researched "{topic}" from AI knowledge (no live sources found).',
            "title": note_title,
            "detail": knowledge[:1000],
            "speak": f"I couldn't find live sources, so here's a summary of {topic} from what I know.",
            "summary": research_summary,
            "data": {
                "topic": topic,
                "sources": [],
                "from_ai_knowledge": True,
                "note_id": note_id,
            },
        }

    # 2. Fetch the top 3 result pages for full content.
    fetched = []
    for s in sources[:3]:
        try:
            page = web_fetch_page({"url": s["url"]})
            fetched.append({
                "title": s.get("title") or page["data"].get("title"),
                "url": s["url"],
                "text": page["data"].get("text", ""),
            })
        except Exception as exc:  # noqa: BLE001 - skip pages that won't load
            logger.info("Research fetch failed for %s: %s", s.get("url"), exc)

    # 3. Synthesize with Groq (graceful fallback to stitched snippets).
    source_lines = "\n".join(
        f"[{i + 1}] {s.get('title')} ({s.get('url')})"
        for i, s in enumerate(sources[:6])
    )
    corpus = "\n\n".join(
        f"SOURCE [{i + 1}] {f.get('title')} ({f.get('url')}):\n{f.get('text')}"
        for i, f in enumerate(fetched)
    )
    try:
        synthesis = _groq_text(
            f"Synthesize this into a {output_format} about {topic}. "
            "Be specific and cite sources by their [number].\n\n"
            f"SOURCES:\n{source_lines}\n\nCONTENT:\n{corpus}"
        )
    except Exception as exc:  # noqa: BLE001 - degrade to a snippet-based summary
        logger.info("Groq synthesis unavailable (%s); using snippet fallback.", exc)
        snippets = "\n".join(
            f"- {s.get('title')}: {s.get('snippet') or s.get('url')}"
            for s in sources[:5]
        )
        synthesis = (
            f"Research summary for {topic} (automatic synthesis unavailable):\n\n"
            f"{snippets}\n\nSources:\n{source_lines}"
        )

    if not synthesis.strip():
        synthesis = f"No content could be synthesized for {topic}.\n\nSources:\n{source_lines}"

    full_content = f"{synthesis}\n\nSources:\n{source_lines}"

    # 4. Save the result as an Apple Note (best-effort; still report the text).
    note_title = f"Research: {topic}"
    note_id = None
    note_status = "success"
    note_error = None
    try:
        note = notes_create_from_image({"title": note_title, "content": full_content})
        note_id = (note.get("data") or {}).get("note_id")
    except Exception as exc:  # noqa: BLE001 - synthesis is still useful without the note
        note_status = "error"
        note_error = str(exc)
        logger.warning("web.research could not save the note: %s", exc)

    saved_msg = (
        f'Researched "{topic}" and saved a {output_format} to Apple Notes.'
        if note_status == "success"
        else f'Researched "{topic}" ({output_format}); could not save the note ({note_error}).'
    )
    research_summary = synthesis[:500]
    if len(synthesis) > 500:
        research_summary += "\n\nSee note for full summary."
    return {
        "tool": "web.research",
        "status": "success",
        "message": saved_msg,
        "title": note_title,
        "detail": synthesis[:1000],
        "speak": (
            f"Done. I've created a note summarizing {topic} for you."
            if note_status == "success"
            else f"I researched {topic} but couldn't save the note."
        ),
        "summary": research_summary,
        "data": {
            "topic": topic,
            "output_format": output_format,
            "synthesis": synthesis,
            "sources": sources[:6],
            "fetched_count": len(fetched),
            "note_id": note_id,
            "note_saved": note_status == "success",
        },
    }


# ----------------------------------------------------------------------------
# Undo builders (Phase 2)
#
# Given a tool's args + result, produce an AppleScript that reverses the action.
# Stored in the action-history DB and run by POST /undo/{id}. Undo is best-effort
# for browser/Gmail (we close the tab we opened) and unavailable where the
# artifact can't be safely reversed (a new untitled sheet, a Drive deck).
# ----------------------------------------------------------------------------

def _close_chrome_tab_script(marker: str) -> str:
    """AppleScript that closes the first Chrome tab whose URL contains marker.

    Iterates tabs back-to-front so closing one doesn't shift later indices.
    """
    m = _as_escape(marker)
    return (
        'tell application "Google Chrome"\n'
        f'    set theMarker to "{m}"\n'
        "    repeat with w in windows\n"
        "        set theTabs to tabs of w\n"
        "        repeat with i from (count theTabs) to 1 by -1\n"
        "            set t to item i of theTabs\n"
        "            if (URL of t) contains theMarker then\n"
        "                close t\n"
        "            end if\n"
        "        end repeat\n"
        "    end repeat\n"
        "end tell"
    )


def build_undo(tool: str, args: dict, result: dict) -> tuple[bool, str | None]:
    """Return (undo_available, undo_script) for a completed tool execution."""
    if not result or result.get("status") != "success":
        return False, None
    data = result.get("data") or {}

    if tool == "notes.create_from_image":
        note_id = data.get("note_id")
        if not note_id:
            return False, None
        return True, (
            'tell application "Notes"\n'
            f'    delete note id "{_as_escape(str(note_id))}"\n'
            "end tell"
        )

    if tool == "numbers.add_expense":
        n = int(data.get("rows_added") or 0)
        path = data.get("file") or EXPENSE_FILE
        if n <= 0:
            return False, None
        return True, (
            'tell application "Numbers"\n'
            "    activate\n"
            f'    set doc to open POSIX file "{_as_escape(path)}"\n'
            "    tell table 1 of sheet 1 of doc\n"
            "        set rc to row count\n"
            f"        if rc - {n} >= 1 then set row count to rc - {n}\n"
            "    end tell\n"
            "    save doc\n"
            "end tell"
        )

    if tool == "gmail.draft_email":
        # Best effort: close the compose tab we opened.
        return True, _close_chrome_tab_script("mail.google.com")

    if tool == "browser.open_url":
        url = data.get("url")
        if not url:
            return False, None
        return True, _close_chrome_tab_script(url)

    if tool == "media.open_spotify":
        return True, 'tell application "Spotify" to pause'

    if tool == "finder.move_file":
        # Reverse the move: mv the file back to its original location.
        src = data.get("source")
        dst = data.get("destination")
        if src and dst:
            return True, (
                'do shell script "mv " & quoted form of "%s" & " " & quoted form of "%s"'
                % (_as_escape(dst), _as_escape(os.path.dirname(src) or "/"))
            )
        return False, None

    if tool == "finder.rename_file":
        old_path = data.get("old_path")
        new_path = data.get("new_path")
        if old_path and new_path:
            return True, (
                'do shell script "mv " & quoted form of "%s" & " " & quoted form of "%s"'
                % (_as_escape(new_path), _as_escape(old_path))
            )
        return False, None

    if tool == "finder.create_folder":
        path = data.get("path")
        if path:
            # rmdir only removes the folder if it is still empty (safe).
            return True, (
                'do shell script "rmdir " & quoted form of "%s"' % _as_escape(path)
            )
        return False, None

    if tool == "calendar.create_event":
        title = data.get("title")
        if title:
            return True, (
                'tell application "Calendar"\n'
                "    repeat with cal in calendars\n"
                f'        delete (every event of cal whose summary is "{_as_escape(title)}")\n'
                "    end repeat\n"
                "end tell"
            )
        return False, None

    if tool == "reminders.add_item":
        title = data.get("title")
        list_name = data.get("list_name") or "Reminders"
        if title:
            return True, (
                'tell application "Reminders"\n'
                f'    tell list "{_as_escape(list_name)}"\n'
                f'        delete (reminders whose name is "{_as_escape(title)}")\n'
                "    end tell\n"
                "end tell"
            )
        return False, None

    # numbers.create_spreadsheet (unsaved/untitled), slides (persists in Drive),
    # clipboard, system settings, and read-only tools have no safe auto-undo.
    return False, None


def run_undo(undo_script: str) -> dict:
    """Execute a stored undo script and return a structured result."""
    if not undo_script:
        return {"status": "error", "message": "No undo script available."}
    try:
        _osascript(undo_script)
        return {"status": "success", "message": "Action undone."}
    except Exception as exc:  # noqa: BLE001 - report failure truthfully
        logger.error("Undo failed: %s", exc)
        return {"status": "error", "message": f"Undo failed: {exc}"}


# ----------------------------------------------------------------------------
# iOS native actions (Phase 5)
#
# These tools don't run anything on the Mac — they return a special
# "ios_action" result carrying a URL scheme. The iOS client (WebSocketClient)
# opens that URL with UIApplication.shared.open so the action happens natively
# on the phone (Reminders, Notes, Maps, Messages).
# ----------------------------------------------------------------------------

def _ios_action(tool: str, title: str, message: str, speak: str, url: str,
                fallback_url: str = "") -> dict:
    """Build the ios_action contract for a phone-side URL-scheme action."""
    return {
        "status": "ios_action",
        "tool": tool,
        "title": title,
        "message": message,
        "speak": speak,
        "url": url,
        "fallback_url": fallback_url,
        "elapsed_ms": 0,
        "data": {"url": url, "fallback_url": fallback_url},
    }


def ios_create_reminder(args: dict) -> dict:
    """Create a reminder natively on the iPhone via a URL scheme (Phase 5)."""
    title = str(args.get("title") or "").strip()
    if not title:
        raise ToolError("ios.create_reminder requires a 'title'.")
    due = str(args.get("due_date") or "").strip()
    q = urllib.parse.urlencode({"title": title})
    # Primary: Reminders' own scheme; fallback: Shortcuts (user "Add Reminder").
    url = f"x-apple-reminderkit://create?{q}"
    sc = {"name": "Add Reminder", "input": title}
    fallback = "shortcuts://run-shortcut?" + urllib.parse.urlencode(sc)
    msg = f'Adding a reminder "{title}"' + (f" due {due}." if due else ".")
    return _ios_action(
        "ios.create_reminder", "New Reminder", msg,
        f"Adding the reminder {title}.", url, fallback,
    )


def ios_create_note(args: dict) -> dict:
    """Create a note natively on the iPhone via the Notes URL scheme (Phase 5)."""
    title = str(args.get("title") or "").strip()
    content = str(args.get("content") or "").strip()
    if not title and not content:
        raise ToolError("ios.create_note requires a 'title' or 'content'.")
    body = "\n".join(p for p in (title, content) if p)
    url = "mobilenotes://new?" + urllib.parse.urlencode({"body": body})
    return _ios_action(
        "ios.create_note", title or "New Note",
        f'Creating a note "{title or content[:30]}" on your phone.',
        "Creating a note on your phone.", url,
    )


def ios_open_maps(args: dict) -> dict:
    """Open Apple Maps on the iPhone for a search query (Phase 5)."""
    query = str(args.get("query") or "").strip()
    if not query:
        raise ToolError("ios.open_maps requires a 'query'.")
    url = "maps://?" + urllib.parse.urlencode({"q": query})
    return _ios_action(
        "ios.open_maps", "Maps", f"Opening Maps for {query}.",
        f"Opening Maps for {query}.", url,
    )


def ios_send_message_draft(args: dict) -> dict:
    """Open a pre-filled Messages draft on the iPhone (Phase 5).

    IRREVERSIBLE — opens a draft addressed to the contact; the user sends it.
    """
    contact = str(args.get("contact") or "").strip()
    message = str(args.get("message") or "").strip()
    if not contact:
        raise ToolError("ios.send_message_draft requires a 'contact'.")
    # sms:{recipient}&body={text} — recipient resolves if it's a number; a name
    # opens the compose sheet for the user to pick the matching contact.
    url = f"sms:{urllib.parse.quote(contact)}&body={urllib.parse.quote(message)}"
    return _ios_action(
        "ios.send_message_draft", "New Message",
        f"Opening a message draft to {contact}.",
        f"Opening a message draft to {contact}.", url,
    )


# ----------------------------------------------------------------------------
# Tool router
# ----------------------------------------------------------------------------

TOOL_REGISTRY = {
    "notes.create_from_image": notes_create_from_image,
    "media.play_pause": media_play_pause,
    "media.next_track": media_next_track,
    "media.previous_track": media_previous_track,
    "media.open_spotify": media_open_spotify,
    "media.open_apple_music": media_open_apple_music,
    "gmail.draft_email": gmail_draft_email,
    "gmail.read_inbox": gmail_read_inbox,
    "gmail.read_email": gmail_read_email,
    "gmail.reply_draft": gmail_reply_draft,
    "browser.open_url": browser_open_url,
    "browser.read_page": browser_read_page,
    "browser.fill_form": browser_fill_form,
    "notes.append_to_note": notes_append_to_note,
    "notes.list_notes": notes_list_notes,
    "numbers.read_sheet": numbers_read_sheet,
    "numbers.edit_cell": numbers_edit_cell,
    "ios.create_reminder": ios_create_reminder,
    "ios.create_note": ios_create_note,
    "ios.open_maps": ios_open_maps,
    "ios.send_message_draft": ios_send_message_draft,
    "slides.create_presentation": slides_create_presentation,
    "numbers.create_spreadsheet": numbers_create_spreadsheet,
    "numbers.add_expense": numbers_add_expense,
    # System control (Phase 1b)
    "system.set_volume": system_set_volume,
    "system.set_brightness": system_set_brightness,
    "system.open_focus_settings": system_open_focus_settings,
    "system.lock_screen": system_lock_screen,
    "system.empty_trash": system_empty_trash,
    "system.get_battery": system_get_battery,
    # Finder / filesystem (Phase 1c)
    "finder.open_file": finder_open_file,
    "finder.find_file": finder_find_file,
    "finder.move_file": finder_move_file,
    "finder.create_folder": finder_create_folder,
    "finder.rename_file": finder_rename_file,
    "finder.show_in_finder": finder_show_in_finder,
    # Clipboard (Phase 1d)
    "clipboard.copy_text": clipboard_copy_text,
    # Calendar (Phase 1e)
    "calendar.create_event": calendar_create_event,
    "calendar.read_today": calendar_read_today,
    "calendar.read_week": calendar_read_week,
    "calendar.find_free_time": calendar_find_free_time,
    # Reminders (Phase 1f)
    "reminders.add_item": reminders_add_item,
    "reminders.read_list": reminders_read_list,
    "reminders.complete_item": reminders_complete_item,
    # Contacts (Phase 1g)
    "contacts.find": contacts_find,
    # Screen awareness (Phase 1h / Phase 5)
    "screen.capture_and_describe": screen_capture_and_describe,
    "screen.capture_and_act": screen_capture_and_act,
    # Web research agent (Phase 6)
    "web.search": web_search,
    "web.fetch_page": web_fetch_page,
    "web.research": web_research,
}

# Tools whose effects are not safely auto-reversible. Phase 2 broadcasts a
# "confirm_required" event and waits for user approval before running these.
IRREVERSIBLE_TOOLS = {
    "finder.move_file",
    "finder.rename_file",
    "system.empty_trash",
    "calendar.create_event",
    "reminders.add_item",
    "gmail.draft_email",
    "gmail.reply_draft",
    "browser.fill_form",
    "ios.send_message_draft",
}


def _error_result(tool: str, exc: Exception, attempts: int, elapsed_ms: float) -> dict:
    """Build the structured error contract for a failed tool execution."""
    return {
        "tool": tool,
        "status": "error",
        "message": f"Failed to execute {tool}: {exc}",
        "title": tool,
        "detail": str(exc),
        "elapsed_ms": elapsed_ms,
        # Spoken error summary (Fix 7).
        "speak": f"I couldn't complete that. {exc}",
        "data": {"error": str(exc), "attempts": attempts},
    }


def _run_with_retry(tool: str, fn, args: dict) -> dict:
    """Run a tool with retry-on-failure, backoff, and latency timing.

    External-app tools fail transiently (app not focused yet, UI not rendered,
    AppleScript "Application isn't running"). We retry up to ``MAX_RETRIES``
    times with ``RETRY_BACKOFF_S`` between attempts. ``ToolError`` signals a
    non-retryable input problem and is reported immediately. Every result
    carries ``elapsed_ms`` so latency regressions are visible.
    """
    start = time.monotonic()
    last_exc: Exception | None = None

    for attempt in range(1, MAX_RETRIES + 2):  # 1..(MAX_RETRIES+1)
        try:
            result = fn(args)
            result.setdefault("status", "success")
            result.setdefault("tool", tool)
            result["elapsed_ms"] = round((time.monotonic() - start) * 1000, 1)
            if attempt > 1:
                logger.info("Tool %s succeeded on attempt %d.", tool, attempt)
            return result
        except ToolError as exc:
            # Bad input — retrying will not help, fail fast and truthfully.
            logger.error("Tool %s input error: %s", tool, exc)
            return _error_result(
                tool, exc, attempt, round((time.monotonic() - start) * 1000, 1)
            )
        except Exception as exc:  # noqa: BLE001 - report failure truthfully
            last_exc = exc
            logger.warning(
                "Tool %s attempt %d/%d failed: %s",
                tool, attempt, MAX_RETRIES + 1, exc,
            )
            if attempt <= MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_S)

    elapsed_ms = round((time.monotonic() - start) * 1000, 1)
    logger.error("Tool %s failed after %d attempts.", tool, MAX_RETRIES + 1)
    return _error_result(tool, last_exc, MAX_RETRIES + 1, elapsed_ms)


def execute(tool: str, args: dict) -> dict:
    """Route a tool call to its execution function and run the real action.

    Returns the structured contract
    ``{"status": "success" | "error", "message": str, "data": dict, ...}``
    with retries, backoff, and ``elapsed_ms`` latency applied uniformly.
    """
    fn = TOOL_REGISTRY.get(tool)
    if fn is None:
        logger.warning("Unknown tool '%s'; falling back to browser.open_url.", tool)
        return _run_with_retry(
            "browser.open_url",
            browser_open_url,
            {"url": str(args.get("query") or args.get("url") or tool)},
        )

    logger.info("Executing tool %s with args %s", tool, args)
    return _run_with_retry(tool, fn, args or {})
