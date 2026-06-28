# Lumis – CLAUDE.md

## Stack
- Backend: Python + FastAPI + uvicorn, SQLite for persistence, deployed on Railway
  (permanent public URL; ngrok only for local dev)
- iOS: Swift + SwiftUI, iOS 17+, AVFoundation, Speech framework, no third-party deps
- Mac: SwiftUI menu bar app, LSUIElement = YES
- AI: Groq llama-4-scout ONLY (multimodal — text + vision)
- Realtime: WebSocket for live event broadcasting
- Mac agent: backend/mac_agent.py runs locally (Railway = brain, mac_agent = hands,
  iOS = eyes/ears). Railway (Linux) can't run osascript/pmset, so macOS-local tools
  are dispatched to the Mac agent over /ws. See "Mac agent split" below.

## Repo layout
backend/        FastAPI server — all AI logic lives here
ios/            SwiftUI iOS app — input layer only
macos-app/      SwiftUI menu bar app — dashboard + tray
web-client/     Single-file HTML/JS fallback frontend

## Hard constraints
- NEVER touch CameraManager.swift or SpeechRecognizer.swift
- NEVER add Python dependencies without asking first
- NEVER put AI logic in any frontend — backend only
- AI Provider: Groq (llama-4-scout) ONLY. No Gemini, no OpenAI, no other
  providers. GROQ_API_KEY is the only required API key. Never add Gemini
  dependencies.
- All API errors must surface in UI, no silent console-only failures
- Dark mode only across all frontends
- SF Pro font, single brand accent color (not blue, not purple)
- Backend deployed on Railway with a permanent public URL; ngrok is for local
  development only
- "ios_action" is a valid result status: the tool returns a phone-side URL
  scheme in the `url` field (with optional `fallback_url`), and the iOS client
  opens it directly with UIApplication.shared.open
- All irreversible tools require confirmation (see IRREVERSIBLE_TOOLS)

## API contracts
POST /ingest        { session_id, image (base64), voice_text, timestamp }
GET  /history       returns last 50 actions
GET  /memory        returns learned user preferences as key/value
DELETE /memory/:key removes one memory entry
GET  /health        returns { status: "ok", latency_ms }
WS   /ws            real-time event stream

## Tool families (backend/tools.py, registered in TOOL_REGISTRY)
All tools return the contract { status, message, title, tool, data, elapsed_ms }.
Two optional fields are also returned and broadcast over WebSocket:
- speak: string — short 1-2 sentence spoken summary (TTS on iOS); empty for
  action-only tools (set_volume, create_folder, open_url, etc.).
- summary: string — longer formatted display text, only for content tools
  (calendar.read_*, reminders.read_list, contacts.find, system.get_battery,
  web.research, screen.capture_and_describe). Drives the iOS summary sheet and
  the Mac dashboard expandable card.
The LLM (backend/llm.py) routes intent to one of these tools.
- content: notes.create_from_image, slides.create_presentation, numbers.create_spreadsheet, numbers.add_expense
- media: media.play_pause, media.next_track, media.previous_track, media.open_spotify, media.open_apple_music
- comms: gmail.draft_email, gmail.read_inbox, gmail.read_email, gmail.reply_draft
- browser: browser.open_url, browser.read_page, browser.fill_form
- notes: notes.create_from_image, notes.append_to_note, notes.list_notes
- numbers: numbers.create_spreadsheet, numbers.add_expense, numbers.read_sheet, numbers.edit_cell
- system: system.set_volume, system.set_brightness, system.open_focus_settings, system.lock_screen, system.empty_trash, system.get_battery
- finder: finder.open_file, finder.find_file, finder.move_file, finder.create_folder, finder.rename_file, finder.show_in_finder
- clipboard: clipboard.copy_text
- calendar: calendar.create_event, calendar.read_today, calendar.read_week, calendar.find_free_time
- reminders: reminders.add_item, reminders.read_list, reminders.complete_item
- contacts: contacts.find
- screen: screen.capture_and_describe, screen.capture_and_act (Groq vision)
- web: web.search, web.fetch_page, web.research (research agent — searches, fetches, synthesizes with Groq, saves a Note)
- ios (native, returns "ios_action" + url for the phone to open): ios.create_reminder, ios.create_note, ios.open_maps, ios.send_message_draft

## Mac agent split (backend/mac_agent.py, engine.py, websocket.py)
Railway can't run osascript/pmset/local-file tools. engine._dispatch routes each
step: CLOUD_TOOLS (ios.*, web.search, web.fetch_page) run on Railway; everything
else is sent to the Mac agent. Flow: engine broadcasts `execute_on_mac`
{action_id, tool, args} and awaits a Future (30s timeout); the Mac agent (a "mac"
WS client that sent {event:"register", role:"mac"}) runs tools.execute() locally
and replies `mac_result` {action_id, result}, which resolves the Future. If no
agent is connected, the step returns "Mac agent not connected. Run mac_agent.py
on your Mac." GET /mac/status reports connection. Run the agent with
run_mac_agent.sh (or the Mac app auto-starts it via MacAgentController and shows
"Mac Agent: Connected/Offline" in the popover). Agent backend URL: $LUMIS_BACKEND_URL.

## Memory (backend/memory.py)
Learns deterministic prefs from successful actions: expense_file, music_service,
last_email_recipient, default_browser, preferred_calendar, preferred_reminder_list,
frequent_contacts, home_folder, command_patterns. memory.get_context_block()
renders all of it as a natural-language paragraph injected into every LLM call.

## Conversation history (backend/llm.py)
Per-session rolling transcript (last 10 turns, last 5 injected as a RECENT
CONVERSATION block) enables follow-ups like "do that again" / "change the time to
3pm". Cleared after 2h of inactivity. session_id is threaded through parse_plan.

## Key patterns
- Backend broadcasts all events over WebSocket — frontends never poll
- All tools return { status: "success"|"error", message: string, data?: any }
- Backend URL stored in UserDefaults key: lumis.backendURL, defaults to http://localhost:8000
- Session IDs prefixed by client type: "ios-", "web-", "mac-"