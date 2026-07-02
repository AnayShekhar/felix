# Lumis — Full Mac Agent Removal & Tool Migration

This is the complete migration. Every tool currently executed via `mac_agent.py`
(AppleScript) must be replaced with either a Google API tool or a Browserbase
cloud browser tool before the Mac agent is deleted. Do not delete anything until
its replacement is working — go tool-by-tool, not folder-first.

---

## Part 1 — Inventory current tools

First, list every tool currently in `TOOL_REGISTRY` (or wherever tools are
registered) that has `"runs_on": "mac"`. For each one, this doc assigns a
replacement strategy below. Do not skip any — if a tool exists in the registry
that isn't covered here, flag it and propose a strategy before proceeding.

---

## Part 2 — Migration map

### Notes → Google Docs (replacement, not equivalent — Apple Notes has no web/API access)

```
notes.create_note        → docs.create_document
notes.create_from_image   → docs.create_document  (with OCR'd/described text as content)
notes.append_to_note      → docs.append_text
notes.list_notes          → drive.search_files (filtered to Docs)
```

Implement in `backend/google_tools.py` using the Google Docs API
(`docs.googleapis.com`), authenticated via the OAuth tokens already captured
during Google account connection (from the cloud browser doc, Part 2).

```python
async def tool_docs_create_document(args: dict, user_id: str) -> dict:
    service = get_google_docs_service(user_id)  # builds authenticated client from stored tokens
    doc = service.documents().create(body={"title": args["title"]}).execute()
    doc_id = doc["documentId"]
    if args.get("content"):
        service.documents().batchUpdate(
            documentId=doc_id,
            body={"requests": [{"insertText": {"location": {"index": 1}, "text": args["content"]}}]}
        ).execute()
    url = f"https://docs.google.com/document/d/{doc_id}"
    return {"status": "success", "title": f"Created '{args['title']}'", "url": url, "speak": "Done — created that doc."}
```

### Numbers → Google Sheets

```
numbers.create_spreadsheet → sheets.create_spreadsheet
numbers.add_expense        → sheets.add_row
numbers.read_sheet         → sheets.read_sheet
numbers.edit_cell          → sheets.edit_cell
```

Implement using Google Sheets API (`sheets.googleapis.com`) — same auth pattern.

```python
async def tool_sheets_add_row(args: dict, user_id: str) -> dict:
    service = get_google_sheets_service(user_id)
    spreadsheet_id = args["spreadsheet_id"]
    values = [args["values"]]
    service.spreadsheets().values().append(
        spreadsheetId=spreadsheet_id,
        range="A1",
        valueInputOption="USER_ENTERED",
        body={"values": values}
    ).execute()
    url = f"https://docs.google.com/spreadsheets/d/{spreadsheet_id}"
    return {"status": "success", "title": "Row added", "url": url, "speak": "Added that to your spreadsheet."}
```

For `numbers.add_expense` specifically: the agent needs to know WHICH spreadsheet
is the user's expense tracker. Use `memory.py` — store `expense_sheet_id` in user
memory the first time they specify one, then default to it on future requests.

### Gmail → Gmail API (already had `gmail.*` tools — just change execution)

```
gmail.draft_email    → same tool, execute via Gmail API instead of AppleScript
gmail.read_inbox      → same tool, Gmail API
gmail.read_email       → same tool, Gmail API
gmail.open_reply        → gmail.reply_to_email via Gmail API (send/save as draft)
```

These were already planned in the earlier cloud browser doc's `google_tools.py` —
confirm they're implemented, or implement now if missing. Use `gmail.googleapis.com`.

### Media (Spotify/Apple Music) → Browserbase browser tools

Apple Music has no useful web control surface. Spotify does (open.spotify.com).

```
media.open_spotify        → browser.open_url with the Spotify Web Player URL,
                             then browser.click to hit play on the specified track/playlist
media.play_pause          → browser.click on the Spotify Web Player play/pause button
media.next_track          → browser.click on next button
media.previous_track      → browser.click on previous button
media.open_apple_music     → DEPRECATED — no web equivalent. Return a clear error:
                             "Apple Music isn't available through Lumis right now —
                             try Spotify instead."
```

```python
async def tool_media_open_spotify(args: dict, user_id: str) -> dict:
    if "spotify" not in get_connected_services(user_id):
        return {"status": "error", "message": "Spotify isn't connected yet.",
                "speak": "You'll need to connect Spotify first."}
    page, session_id = await get_page_for_user(user_id)
    try:
        query = args.get("search_query", "")
        await page.goto(f"https://open.spotify.com/search/{query}")
        await page.wait_for_timeout(1500)
        first_result = page.locator('[data-testid="tracklist-row"]').first
        await first_result.click()
        return {"status": "success", "title": "Playing on Spotify",
                "url": page.url, "speak": f"Playing {query} on Spotify."}
    finally:
        await close_cloud_session(session_id)
```

### Browser (Chrome) — already covered

`browser.open_url`, `browser.read_page`, `browser.fill_form`, `browser.click`,
`browser.screenshot` — already specified in the cloud browser doc's Part 4. Confirm
implemented against `get_cloud_page`/Browserbase, not local Playwright.

### Calendar → Google Calendar API (already had `calendar.*` tools)

```
calendar.create_event    → Google Calendar API
calendar.read_today       → Google Calendar API
calendar.read_week         → Google Calendar API
calendar.find_free_time    → Google Calendar API (freebusy query)
```

Confirm implemented in `google_tools.py` per the cloud browser doc — these do not
need browser automation at all.

### Reminders → Google Tasks API (closest equivalent)

Apple Reminders has no API. Google Tasks is the direct equivalent and has a clean API.

```
reminders.add        → tasks.create_task  (Google Tasks API)
reminders.read         → tasks.list_tasks
reminders.complete      → tasks.complete_task
```

```python
GOOGLE_SCOPES.append("https://www.googleapis.com/auth/tasks")
```

### Contacts → Google Contacts (People API)

```
contacts.lookup       → people.search_contacts (Google People API)
contacts.get_email     → people.search_contacts, extract email
contacts.get_phone     → people.search_contacts, extract phone
```

```python
GOOGLE_SCOPES.append("https://www.googleapis.com/auth/contacts.readonly")
```

### System controls (volume, brightness, lock screen, trash, battery, Focus)

**These have no cloud equivalent — they require physical access to the Mac.**
DEPRECATE entirely. Remove from `TOOL_REGISTRY` and the agent prompt's tool list.
If a user asks for one of these, the agent should say clearly:
"That's a system-level Mac action — Lumis can't do that without the Mac app,
which isn't available right now."

Add to `agent_prompt.py`:
```
DEPRECATED CAPABILITIES
Lumis cannot control system settings (volume, brightness, lock screen, trash,
battery status, Focus mode). If asked, explain this clearly and briefly —
don't attempt a workaround.
```

### Finder (file operations) → Google Drive

```
finder.find_file          → drive.search_files
finder.open_file            → drive.get_file_link (returns a Drive URL, not local file)
finder.move_file             → drive.move_file (moves within Drive folders)
finder.rename_file            → drive.rename_file
finder.create_folder            → drive.create_folder
finder.reveal_in_finder          → DEPRECATED — no equivalent, just return the Drive link
```

Note: this only works for files that live in Google Drive. Local-only files on
the user's Mac are no longer accessible at all — this is a real capability loss,
inherent to dropping the Mac agent. Be upfront with users about this limitation.

### Clipboard → DEPRECATED

No cloud equivalent — clipboard is a local OS concept. Remove entirely.

### Screen capture → Browserbase screenshot only

`capture_screen` (full Mac screen) is gone. `browser.screenshot` (browser tab
only) remains as the only visual verification tool. Update `agent_prompt.py` to
remove any reference to full-screen capture — the agent can now only see the
browser, not the whole Mac screen (which no longer exists in this architecture).

### Web tools — unchanged

```
web.search       → stays as-is, cloud-side, no Mac dependency
web.fetch_page    → stays as-is
web.research       → stays as-is
```

### iOS native tools — unchanged

```
ios.create_reminder    → stays as-is, opens URL scheme on phone directly
ios.create_note          → stays as-is
ios.open_maps              → stays as-is
ios.draft_message            → stays as-is
```

These never depended on the Mac agent — they always executed via URL scheme
directly on the iPhone.

---

## Part 3 — Update TOOL_REGISTRY completely

Rewrite `backend/tools.py`'s `TOOL_REGISTRY` — every entry now has `"runs_on"` of
either `"google_api"` or `"cloud_browser"` or `"ios_native"`. No entry should say
`"mac"` anywhere after this migration.

```python
TOOL_REGISTRY = {
    # Google API tools
    "docs.create_document":    {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "docs.append_text":         {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.create_spreadsheet": {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.add_row":              {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.read_sheet":             {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "sheets.edit_cell":                {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "gmail.draft_email":                 {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "gmail.send_email":                    {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},
    "gmail.read_inbox":                       {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "calendar.create_event":                    {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "calendar.read_today":                         {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "tasks.create_task":                              {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "tasks.complete_task":                               {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},
    "people.search_contacts":                               {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "drive.search_files":                                      {"runs_on": "google_api", "irreversible": False, "requires_service": "google"},
    "drive.move_file":                                            {"runs_on": "google_api", "irreversible": True,  "requires_service": "google"},

    # Cloud browser tools
    "browser.open_url":        {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.read_page":         {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.fill_form":            {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.click":                   {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "browser.screenshot":                 {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "media.open_spotify":                    {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "spotify"},
    "media.play_pause":                         {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "spotify"},
    "notion.create_page":                          {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "notion"},
    "notion.append_to_page":                          {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "notion"},
    "linkedin.post_update":                              {"runs_on": "cloud_browser", "irreversible": True,  "requires_service": "linkedin"},
    "slack.send_message":                                   {"runs_on": "cloud_browser", "irreversible": True,  "requires_service": "slack"},
    "airtable.add_record":                                     {"runs_on": "cloud_browser", "irreversible": False, "requires_service": "airtable"},

    # Web (no auth needed)
    "web.search":         {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "web.fetch_page":       {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},
    "web.research":           {"runs_on": "cloud_browser", "irreversible": False, "requires_service": None},

    # iOS native
    "ios.create_reminder":  {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.create_note":         {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.open_maps":              {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
    "ios.draft_message":             {"runs_on": "ios_native", "irreversible": False, "requires_service": None},
}
```

### Removed entirely (no replacement — deprecated)

```
system.set_volume, system.set_brightness, system.lock_screen, system.empty_trash,
system.get_battery, system.open_focus, clipboard.copy, finder.reveal_in_finder,
media.open_apple_music, capture_screen (full-screen — browser.screenshot replaces
it for browser-only visual verification)
```

---

## Part 4 — Update `agent.py` routing

Replace the `runs_on == "mac"` branch entirely:

```python
async def _handle_tool_call(self, decision: dict):
    tool_name = decision.get("tool")
    tool_args = decision.get("args", {})
    tool_meta = TOOL_REGISTRY.get(tool_name)

    if tool_meta is None:
        result = {"status": "error", "message": f"Unknown tool: {tool_name}"}
    elif tool_meta.get("requires_service") and tool_meta["requires_service"] not in get_connected_services(self.user_id):
        result = {
            "status": "error",
            "message": f"{tool_meta['requires_service']} isn't connected.",
            "speak": f"You'll need to connect {tool_meta['requires_service']} first."
        }
        await self.broadcast({"event": "service_required", "session_id": self.session_id,
                               "service": tool_meta["requires_service"], "message": result["message"], "speak": result["speak"]})
        return
    elif tool_meta.get("runs_on") == "google_api":
        result = await execute_google_tool(tool_name, tool_args, self.user_id)
    elif tool_meta.get("runs_on") == "cloud_browser":
        result = await execute_browser_tool(tool_name, tool_args, self.user_id)
    elif tool_meta.get("runs_on") == "ios_native":
        result = await execute_ios_tool(tool_name, tool_args, self.user_id)
    else:
        result = {"status": "error", "message": f"No execution path for {tool_name}"}

    # ... rest unchanged (broadcast, memory update, context append)
```

Remove all references to `send_to_mac`, `wait_for_mac_result`, and the
`capture_screen` special action (replaced entirely by `browser.screenshot` as a
normal tool call, not a special agent action type).

---

## Part 5 — Update agent_prompt.py tool list

Replace the entire tool list section with the migrated set from Part 3. Add this
rule near the top:

```
CAPABILITY BOUNDARIES
Lumis no longer has access to: local Mac files outside Google Drive, system
settings (volume/brightness/lock/trash/battery/Focus), Apple Notes, Apple
Reminders, Apple Music, or the clipboard. If asked for any of these, say clearly
that it's not available right now rather than attempting a workaround. Suggest
the closest available alternative (e.g. Google Docs instead of Notes, Google
Tasks instead of Reminders, Spotify instead of Apple Music).
```

---

## Part 6 — Now delete the Mac agent

Only after Parts 1-5 are complete and each replacement tool is verified working:

```bash
rm -rf macos-app
rm backend/mac_agent.py
rm backend/mac_bridge.py
rm backend/linking.py
rm backend/vision.py   # full-screen capture, replaced by browser.screenshot
```

Remove all `/link/*` routes from `backend/routes.py`. Remove Mac socket handling
from `backend/websocket.py` — only iPhone clients connect now.

```bash
grep -ril "macos-app\|mac_agent\|mac_bridge\|linking.py\|MacConnectionViewModel\|MacLinkingView\|MacDetailView" . --exclude-dir=.git --exclude-dir=node_modules
```

Fix every remaining result.

---

## Part 7 — Update README.md

Rewrite the architecture section to reflect: iPhone → Railway (Groq agent) →
Google APIs (for Google services) + Browserbase cloud browser (for everything
else) → results land directly in the user's real accounts. Remove all mentions of
the Mac app, Mac agent, AppleScript, and pairing codes.

---

## Part 8 — Verification

```bash
# No Mac references anywhere
grep -ril "mac_agent\|macos-app\|osascript" . --exclude-dir=.git --exclude-dir=node_modules
# Expected: no output

# No tool in the registry still says "mac"
grep -A1 "TOOL_REGISTRY" backend/tools.py | grep '"mac"'
# Expected: no output
```

Manual end-to-end tests — run one command per category and confirm it actually
works against real accounts:

- [ ] "Create a doc titled Meeting Notes" → real Google Doc appears in user's Drive
- [ ] "Add $12 lunch to my expenses" → real row appears in user's Google Sheet
- [ ] "Draft an email to Sam" → real draft appears in user's Gmail
- [ ] "What's on my calendar today" → reads real Google Calendar
- [ ] "Remind me to call mom tomorrow" → real Google Task created
- [ ] "Play some jazz on Spotify" → real Spotify Web Player session plays music
- [ ] "Create a Notion page about this" → real Notion page created
- [ ] "Set my volume to 50" → agent responds that this isn't available, does not crash
- [ ] "Find my resume" → searches Google Drive, not local Mac files — confirm
      response makes clear it only searches Drive
- [ ] Asking for an unconnected service → `service_required` event fires, iOS
      shows the connect prompt from the previous iOS doc
- [ ] Full app functions with zero references to `macos-app/` anywhere in the repo