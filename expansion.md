# Felix Expansion — Cloud + Tools

Complete each phase fully. Summarize every
file changed after each phase and wait for
confirmation before proceeding.

---

## PHASE 1: Railway deployment

Goal: permanent public URL so iOS and Mac
work without ngrok or same WiFi ever again.

In backend/main.py:
- Read port from environment variable PORT
- Use 0.0.0.0 as host
- Add startup log showing which port

In backend/db.py:
- Read SQLite path from environment variable
  FELIX_DB_PATH
- Fall back to local actions.db if not set
- Create parent directories if they don't exist

In backend/memory.py:
- Read memory path from environment variable
  FELIX_MEMORY_PATH
- Fall back to local memory.json if not set
- Create parent directories if they don't exist

Create backend/Procfile:
  web: uvicorn main:app --host 0.0.0.0
       --port $PORT

Create backend/railway.toml:
  [build]
  builder = "nixpacks"
  [deploy]
  startCommand = "uvicorn main:app
    --host 0.0.0.0 --port $PORT"
  restartPolicyType = "on_failure"
  restartPolicyMaxRetries = 3
  healthcheckPath = "/health"
  healthcheckTimeout = 10

Create backend/.env.example:
  GROQ_API_KEY=your_groq_key_here
  GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
  PORT=8000
  FELIX_DB_PATH=/app/data/actions.db
  FELIX_MEMORY_PATH=/app/data/memory.json

Ensure CORS in backend/main.py allows all
origins, methods, and headers.

In ios/FelixApp/FelixApp/ContentView.swift:
Change fallbackURL to "RAILWAY_URL_HERE"
with comment: // Replace after Railway deploy

In macos-app/Felix/Felix/AppEnvironment.swift:
Change default backend URL to "RAILWAY_URL_HERE"
with same comment.

Create DEPLOY.md in project root:

  # Deploying Felix to Railway

  1. Push repo to GitHub
  2. Go to railway.app, sign up free
  3. New Project → Deploy from GitHub
  4. Select felix repo
  5. Set root directory to: backend
  6. Add environment variables:
     GROQ_API_KEY = your key
     GROQ_MODEL = meta-llama/llama-4-scout-17b-16e-instruct
  7. Copy the generated Railway URL
  8. Replace RAILWAY_URL_HERE in:
     - ios/FelixApp/FelixApp/ContentView.swift
     - macos-app/Felix/Felix/AppEnvironment.swift
  9. Rebuild iOS app and install on phone
  10. Rebuild Mac app and run on Mac
  11. Never use ngrok again

  To verify: curl https://your-url/health
  Should return: {"status":"ok"}

---

## PHASE 2: Email reading tools

Add to backend/tools.py.
All use Mail.app via AppleScript.
All return speak and summary fields.

### gmail.read_inbox
args: { count?: int default 10 }

Read messages from Mail.app inbox.
Return sender, subject, date, and first
200 characters of content per message.

speak: how many emails, who the latest
is from and what it's about.

summary: formatted list of all emails with
sender, subject, date, and preview separated
by divider lines.

### gmail.read_email
args: { subject_query: string }

Find first message in inbox whose subject
contains the query. Return full content.

If not found return structured error with
helpful message.

speak: who it's from and what it's about.
summary: full formatted email with sender,
subject, date, and body.

### gmail.reply_draft
args: { subject_query: string,
  reply_body: string }

Find the email and open a pre-filled reply
window in Mail.app.
Mark as IRREVERSIBLE.

speak: drafted a reply, user should review
before sending.
summary: who the reply is to, subject,
and the reply body.

---

## PHASE 3: Browser tools

Add to backend/tools.py.

### browser.read_page
args: none

Get URL and title of frontmost Chrome tab
via AppleScript. Fetch page using requests
and BeautifulSoup already in requirements.txt.
Strip all HTML, scripts, nav, footer, header.
Return first 3000 characters of clean text.

speak: what page the user is on.
summary: page title, URL, and extracted text.

### browser.fill_form
args: { fields: [{ selector: string,
  value: string }] }

Execute JavaScript in frontmost Chrome tab
to set each field value and dispatch input
and change events.
Mark as IRREVERSIBLE.

speak: how many fields filled, user should
review before submitting.
summary: list of selectors and values filled.

---

## PHASE 4: Document editing tools

Add to backend/tools.py.

### notes.append_to_note
args: { title: string, content: string }

Find note in Notes.app whose name contains
the title. Append content to the end.
If not found create a new note.

speak: added to the note.

### notes.list_notes
args: { count?: int default 10 }

List recent notes from Notes.app with name
and modification date.

speak: how many notes and what the most
recent is called.
summary: formatted list with dates.

### numbers.read_sheet
args: { file_path?: string }

If file_path provided expand with
os.path.expanduser and open it first.
Read up to 20 rows from first table of
first sheet in frontmost Numbers window.

speak: how many rows the spreadsheet has.
summary: first 20 rows as readable table.

### numbers.edit_cell
args: { row: int, column: int,
  value: string }

Set specific cell value in frontmost
Numbers window via AppleScript.

speak: what cell was updated and to what.

---

## PHASE 5: iOS native actions

The Mac backend returns a special response.
The iOS client opens the URL directly.

### Backend changes

Add helper function _ios_action to tools.py
that returns a dict with:
- status: "ios_action"
- tool: tool name
- title: display title
- message: one line description
- speak: what Felix says
- url: the URL scheme to open
- elapsed_ms: 0

### ios.create_reminder
args: { title: string, due_date?: string }

Return ios_action with x-apple-reminderkit
URL scheme. Fall back to shortcuts URL scheme.
speak: adding the reminder.

### ios.create_note
args: { title: string, content: string }

Return ios_action with mobilenotes URL scheme.
speak: creating a note on the phone.

### ios.open_maps
args: { query: string }

Return ios_action with maps:// URL scheme.
speak: opening Maps for the query.

### ios.send_message_draft
args: { contact: string, message: string }

Return ios_action with sms URL scheme.
Mark as IRREVERSIBLE.
speak: opening a message draft.

### iOS client changes

In WebSocketClient.swift when handling
step_executed events:

If data.status equals "ios_action" and
data.url is a valid URL, open it with
UIApplication.shared.open on the main thread.
Existing result toast still shows using
the message field.

---

## PHASE 6: Enhanced media tools

Remove spotify.play_song entirely.
Add to backend/tools.py:

### media.play_pause
args: none

Send play/pause media key via System Events.
Key code 100.
speak: toggled playback.

### media.next_track
args: none

Send next track key via System Events.
Key code 101.
speak: skipping to next track.

### media.previous_track
args: none

Send previous track key via System Events.
Key code 98.
speak: going back.

### media.open_spotify
args: { query?: string }

If query: open spotify:search:{encoded_query}
Else: open spotify:
Wait 1.5 seconds then send play key code 100.
speak: opening Spotify, mention query if given.

### media.open_apple_music
args: { query?: string }

Use AppleScript to activate Music app.
If query provided search for it.
speak: opening Apple Music.

---

## PHASE 7: Update LLM system prompt

In backend/llm.py update the complete tools
list and add routing rules for all new tools:

EMAIL:
- read my email, check inbox, any emails →
  gmail.read_inbox
- read the email about X, email from X →
  gmail.read_email
- reply to, respond to email →
  gmail.reply_draft

BROWSER:
- what's on this page, read this page,
  summarize this site → browser.read_page
- fill in this form, fill out →
  browser.fill_form

NOTES:
- add to my note, append to, update note →
  notes.append_to_note
- list my notes, what notes do I have →
  notes.list_notes

SPREADSHEET:
- what's in my spreadsheet, read my sheet →
  numbers.read_sheet
- edit cell, change row X column Y →
  numbers.edit_cell

IOS NATIVE:
- remind me on my phone →
  ios.create_reminder
- note on my phone →
  ios.create_note
- directions to, navigate to, open maps →
  ios.open_maps
- text X, message X →
  ios.send_message_draft

MEDIA:
- play, pause, resume → media.play_pause
- next, skip → media.next_track
- previous, go back → media.previous_track
- open Spotify, play X on Spotify →
  media.open_spotify
- open Apple Music, play X on Apple Music →
  media.open_apple_music

---

## PHASE 8: Update CLAUDE.md

Update tool registry to include all tools
added in Phases 2 through 6.

Update constraints to add:
- Backend deployed on Railway
- ngrok only for local development
- ios_action is a valid status type
- iOS client opens url field directly
- All tools return speak field
- Content tools return summary field

---

## Constraints throughout all phases
- Groq only, no Gemini, no OpenAI
- Never touch CameraManager.swift or
  SpeechRecognizer.swift
- No new Python dependencies without
  adding to requirements.txt explicitly
- All errors return structured results
- All irreversible tools require confirmation
- Dark mode only
- Amber #F59E21 throughout
- SF Pro fonts only
- Existing WebSocket events unchanged
- Only add new fields and event types
- Run test_tools.py after Phase 6