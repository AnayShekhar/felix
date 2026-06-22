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
import logging
import os
import subprocess
import time
import urllib.parse

logger = logging.getLogger("felix.tools")

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
        "data": {"note_id": note_id, "title": title},
    }


def spotify_play_song(args: dict) -> dict:
    """Open Spotify, search the song, and play the top result via UI scripting.

    `spotify:search:` only opens the search view, and the desktop app's
    AppleScript `play` merely resumes the last track. So we drive the keyboard
    through System Events to select and play the first search result.

    Requires macOS Accessibility permission for the app running this process
    (System Settings -> Privacy & Security -> Accessibility).
    """
    query = str(args.get("query") or args.get("song") or "").strip()
    if not query:
        raise ToolError("spotify.play_song requires a 'query'.")

    # Launch Spotify on the search results for this query.
    search_uri = "spotify:search:" + urllib.parse.quote(query)
    subprocess.run(["open", search_uri], check=True)

    # Latency optimization: the old code blocked on a fixed `delay 2.5` even
    # when results rendered sooner. Instead, poll for the top result's "Play"
    # button (matched by its accessibility description, e.g. "Play Song by
    # Artist") every 0.2s and click it the instant it appears — typically well
    # under a second on a warm app. We cap the wait at ~5s, then fall back to
    # keyboard navigation so playback still starts on a slow render.
    script = (
        'tell application "Spotify" to activate\n'
        'tell application "System Events"\n'
        '    tell process "Spotify"\n'
        "        set frontmost to true\n"
        "        set clicked to false\n"
        "        repeat 25 times\n"
        "            try\n"
        "                set playButtons to (every button of (entire contents) "
        'whose description starts with "Play")\n'
        "                if (count of playButtons) > 0 then\n"
        "                    click (item 1 of playButtons)\n"
        "                    set clicked to true\n"
        "                    exit repeat\n"
        "                end if\n"
        "            end try\n"
        "            delay 0.2\n"
        "        end repeat\n"
        "        if not clicked then\n"
        "            key code 48\n"  # tab -> focus into results
        "            delay 0.3\n"
        "            key code 125\n"  # down -> highlight top result
        "            delay 0.3\n"
        "            key code 36\n"  # return -> play
        "        end if\n"
        "    end tell\n"
        "end tell"
    )
    _osascript(script)
    return {
        "tool": "spotify.play_song",
        "status": "success",
        "message": f'Searched and played the top result for "{query}" in Spotify.',
        "title": query,
        "detail": f"spotify:search:{query}",
        "data": {"query": query, "search_uri": search_uri},
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

    if tool == "spotify.play_song":
        return True, 'tell application "Spotify" to pause'

    # numbers.create_spreadsheet (unsaved/untitled) and slides (persists in
    # Drive) have no safe automatic undo.
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
# Tool router
# ----------------------------------------------------------------------------

TOOL_REGISTRY = {
    "notes.create_from_image": notes_create_from_image,
    "spotify.play_song": spotify_play_song,
    "gmail.draft_email": gmail_draft_email,
    "browser.open_url": browser_open_url,
    "slides.create_presentation": slides_create_presentation,
    "numbers.create_spreadsheet": numbers_create_spreadsheet,
    "numbers.add_expense": numbers_add_expense,
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
