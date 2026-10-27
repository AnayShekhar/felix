# Felix – CLAUDE.md

## Stack
- Backend: Python + FastAPI + uvicorn, SQLite for persistence, deployed on Railway
  (permanent public URL; ngrok only for local dev)
- iOS: Swift + SwiftUI, iOS 17+, AVFoundation, Speech framework, no third-party deps
- Chrome extension: Manifest V3, vanilla JS — auth + cookie sync only (no automation)
- AI: Groq ONLY (multimodal — text + vision; default `qwen/qwen3.6-27b`)
- Realtime: WebSocket for live event broadcasting
- Execution is 100% cloud (Railway = brain, iOS = eyes/ears). Tools run three ways:
  Google REST APIs, a Browserbase cloud browser, or a phone-side URL scheme.
  See "Cloud execution split" below. There is NO Mac app / Mac agent / osascript.

## Repo layout
backend/           FastAPI server — all AI + tool logic lives here
ios/               SwiftUI iOS app — input layer only
chrome-extension/  "Connect your accounts" browser extension (auth + cookie sync)

## Hard constraints
- NEVER touch CameraManager.swift or SpeechRecognizer.swift
- NEVER add Python dependencies without asking first
- NEVER put AI logic in any frontend — backend only
- AI Provider: Groq ONLY. No Gemini, no direct OpenAI, no other providers.
  Default model is `qwen/qwen3.6-27b` (multimodal; replaces shut-down
  `meta-llama/llama-4-scout-17b-16e-instruct`). GROQ_API_KEY is the only
  required AI key. Never add Gemini dependencies. (google-* packages are for
  Google service APIs / auth, NOT AI. `openai/gpt-oss-*` on Groq is still Groq.)
- All API errors must surface in UI, no silent console-only failures
- Adaptive light/dark theme across frontends from three raw colors: Carbon
  #212222, Alabaster #DBDDDE, Cool Steel #99ACBE. Light: Alabaster bg / Carbon
  text; dark: swapped; the tint (Cool Steel) is constant in both modes. iOS
  uses semantic `FelixColors` tokens (never raw hex outside that file) plus
  `FelixSpacing`/`FelixRadius`; the extension mirrors them as CSS custom
  properties with `prefers-color-scheme`. Users can override System/Light/Dark
  in iOS Settings (`FelixAppearance`). shared/Constants.swift (`FelixBrand`)
  mirrors the light-mode hex values.
- SF Pro font everywhere except the New York serif home greeting; single brand
  accent (Cool Steel). The app shell is Home + slide-in sidebar + Settings
  sheet (no tab bar).
- Backend deployed on Railway with a permanent public URL; ngrok is for local
  development only
- "ios_action" is a valid result status: the tool returns a phone-side URL
  scheme in the `url` field (with optional `fallback_url`), and the iOS client
  opens it directly with UIApplication.shared.open
- Irreversible tools are flagged in TOOL_REGISTRY (`irreversible: true`), surfaced
  as IRREVERSIBLE_TOOLS; be confident of args before calling one (the agent is
  told to ask_user if unsure).

## API contracts
POST /ingest               { session_id, image (base64), voice_text }
GET  /history              returns last 50 actions
GET  /memory               returns learned user preferences as key/value
DELETE /memory/:key        removes one memory entry
GET  /connect/status       { connected: [service, …] } for the signed-in account
POST /connect/cookies/sync  Chrome extension → inject cookies into Browserbase ctx
GET  /health               returns { status: "ok" }
WS   /ws                   real-time event stream (broadcast-only to clients)

## Tool families (backend/tools.py TOOL_REGISTRY — metadata, not callables)
Each registry entry is { runs_on, irreversible, requires_service }. `runs_on` is
one of "google_api" | "cloud_browser" | "ios_native". Tools return the contract
{ status, message, title, tool, data, elapsed_ms } plus optional:
- speak: short 1-2 sentence spoken summary (TTS on iOS); empty for action-only tools.
- summary: longer formatted display text for content tools (sheets.read_sheet,
  calendar.read_today, gmail.read_inbox, people.search_contacts, drive.search_files,
  web.research). Drives the iOS summary sheet.
The ReAct agent (backend/agent.py) picks one tool per step and routes by runs_on.

- google_api (backend/google_tools.py — needs Google connected):
  docs.create_document, docs.append_text, sheets.create_spreadsheet, sheets.add_row
  (set args.expense=true to use the remembered expense sheet), sheets.read_sheet,
  sheets.edit_cell, gmail.draft_email, gmail.send_email (IRREVERSIBLE), gmail.read_inbox,
  calendar.create_event, calendar.read_today, tasks.create_task, tasks.complete_task,
  people.search_contacts, drive.search_files, drive.move_file
- cloud_browser (backend/browser_tools.py — Browserbase, signed in via synced cookies):
  browser.open_url, browser.read_page, browser.click, browser.fill_form,
  browser.screenshot, media.open_spotify, media.play_pause, notion.create_page,
  notion.append_to_page, linkedin.post_update, slack.send_message, airtable.add_record
- web (backend/tools.py — keyless HTTP, no auth/browser): web.search, web.fetch_page,
  web.research (searches, synthesizes with Groq, saves a Google Doc if connected)
- ios_native (backend/tools.py — returns "ios_action" + url for the phone to open):
  ios.create_reminder, ios.create_note, ios.open_maps, ios.send_message_draft

## ReAct agent (backend/agent.py, agent_prompt.py)
/ingest runs a deep ReAct loop on Groq: THINK -> ACT (one tool) ->
OBSERVE the real result -> repeat, until the agent emits `finish` or hits
AGENT_MAX_STEPS (default 20). One JSON action per turn: tool_call | ask_user
(pauses; resumed via the next /ingest on the same session_id, or POST /agent/reply)
| finish. There is no capture_screen action — the only visual check is the
browser.screenshot tool (its image is fed back into the loop). The agent emits
agent_* events AND backward-compatible step_started/step_executed/workflow_complete
so the iOS app keeps working. routes.active_agents holds paused sessions.

## Cloud execution split (backend/agent.py, tools.py, google_tools.py, browser_tools.py)
Before running a tool the agent gates on the account it needs (TOOL_REGISTRY
requires_service): "google" is satisfied by google_oauth.has_google(user_id);
other services (spotify/notion/…) by connections.get_connected_services(user_id).
If missing, the agent emits a `service_required` event {service, message, speak}
and the iOS app tells the user which account to connect. Otherwise it dispatches:
- runs_on google_api    -> google_tools.execute_google_tool(tool, args, user_id)
- runs_on cloud_browser -> browser_tools.execute_browser_tool(tool, args, user_id)
  (web.* delegated to tools.execute_cloud_tool; no browser/auth needed)
- runs_on ios_native    -> tools.execute_ios_tool(tool, args, user_id)

## Account connections (backend/connections.py, cloud_browser.py, google_oauth.py)
The Chrome extension signs into the user's Felix account (reusing /auth/*), then
syncs each service's logged-in cookies to POST /connect/cookies/sync, which injects
them into the user's persistent Browserbase context (cloud_browser.py). connections
stores the per-user context id + connected-services set. Google REST tools need
OAuth tokens (google_oauth.py), which cookies do NOT provide — until a Google OAuth
consent flow populates that store, Google tools return a clean "connect Google"
error. Config: BROWSERBASE_API_KEY, BROWSERBASE_PROJECT_ID, GOOGLE_OAUTH_CLIENT_ID,
GOOGLE_OAUTH_CLIENT_SECRET.

## Memory (backend/memory.py)
Learns deterministic prefs from successful actions (e.g. expense_sheet_id,
last_email_recipient, frequent_contacts, command_patterns). memory.get_context_block()
renders all of it as a natural-language paragraph injected into the agent's first
message every run. Set a pref with memory.set_pref(key, value).

## Conversation history (backend/agent.py)
Per-session rolling transcript (last 10 turns, last 5 injected as a RECENT
CONVERSATION block) enables follow-ups like "do that again" / "change the time to
3pm". Cleared after 2h of inactivity. A fresh agent is created per /ingest, so
this transcript (not the live loop context) carries cross-command memory.

## Key patterns
- Backend broadcasts all events over WebSocket — frontends never poll
- All tools return { status: "success"|"error"|"ios_action", message, data?, … }
- Backend URL: FelixConfig.backendURL (iOS); auth token in the Keychain
- Session IDs prefixed by client type: "ios-", "web-"
