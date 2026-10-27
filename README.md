# Felix

## What is Felix?

Felix is a magic assistant that lives in your phone and acts on your real accounts.
You point your phone's camera at something in real life (a whiteboard, a receipt,
some messy notes), you say what you want out loud, and Felix actually goes and does
it — drafts the email, logs the expense, creates the doc, plays the song. For real.
Not fake.

The big idea: **the brain of Felix is the backend, and the hands are your cloud
accounts.** The phone app is the eyes and ears. All the smart stuff happens in one
place (the cloud), so Felix can act whether or not any particular device is on.

A normal app makes you type and tap. Felix lets you just *show it* something and
*tell it* what to do, and then it turns real life into things happening in your
Google account, your browser, and on your phone.

### A quick example

1. You open the Felix app and point it at a receipt.
2. You say: **"Hey Felix, add this to my expense spreadsheet."**
3. The phone sends the picture + your words to the backend.
4. The backend reads the receipt with AI, figures out the store, date, and price.
5. It appends a row to your **Google Sheet** via the Sheets API. Done.

---

## The three pieces (brain / eyes / hands)

- **The brain 🧠 — the backend on Railway.** It gets the picture + voice, runs a
  ReAct agent on Groq (`qwen/qwen3.6-27b`), remembers your preferences, and decides what
  to do. It lives at a permanent public URL in the cloud.
- **The eyes & ears 👀 — the iPhone app.** Camera + microphone + the chat screen. It
  captures the real world and shows you results. It never makes decisions.
- **The hands ✋ — your connected accounts.** Everything runs in the cloud:
  - **Google APIs** for Docs, Sheets, Gmail, Calendar, Tasks, Contacts, and Drive.
  - **A Browserbase cloud browser** for everything else (Spotify, Notion, Slack,
    LinkedIn, Airtable, and general web browsing) — signed in using the cookies you
    sync from the **Felix Chrome extension**.

So a single command travels **phone → cloud brain → your real accounts → back to the
phone**, live, in a couple of seconds. There is no Mac app and nothing to install on
a computer except the browser extension.

---

## Accounts & connections

Felix is account-based, so everything is scoped to one login and one memory.

- **Sign in.** Email + password, **Sign in with Apple**, or **Sign in with Google**.
  Sessions are JWTs (30 days); passwords are hashed with PBKDF2. On iOS the token
  lives in the Keychain.
- **Connect your accounts.** Install the **Felix Chrome extension**
  (`chrome-extension/`), sign in with the same Felix account, and click *Connect* on
  the services you want (Gmail, Sheets, Notion, Spotify, …). The extension syncs your
  logged-in cookies into your private Browserbase context so Felix is already signed
  in when it acts. `GET /connect/status` reports what's connected.
- **Graceful when something isn't connected.** If you ask for a service you haven't
  linked, the agent emits a `service_required` event and the app tells you exactly
  what to connect — it never fails silently.
- **Per-account memory.** Everything Felix learns (your expense sheet, who you email
  most) is scoped to your account.

---

## What Felix can do

| Family | Examples |
| --- | --- |
| **Docs** | Create and append to Google Docs. |
| **Sheets** | Create spreadsheets, log expenses, read and edit cells. |
| **Gmail** | Draft, send, and read email. |
| **Calendar** | Create events, read today's schedule. |
| **Tasks** | Create and complete Google Tasks (replaces reminders). |
| **Contacts** | Look people up in Google Contacts. |
| **Drive** | Search and move files (Drive only — no local files). |
| **Browser** | Open pages, read them, click, fill forms, screenshot — on a real cloud browser signed in as you. |
| **Media** | Play/pause and search Spotify via the web player. |
| **Other** | Notion, Slack, LinkedIn, Airtable via the cloud browser. |
| **Web** | Search, fetch a page, or run a research agent that searches + synthesizes + saves a Google Doc. |
| **iPhone** | Create a reminder/note, open Maps, draft an iMessage — via URL schemes on the phone itself. |

The agent looks at its own work when it matters: mid-task it can call
`browser.screenshot` to see the cloud browser and verify an action worked before
finishing.

---

## Architecture

Felix has three layers, all in the cloud behind the backend:

```
┌────────────────────────────────────────────────────┐
│  LAYER 1: The Frontend (iPhone app)                │
│  - camera + mic + chat UI                          │
│  - sends { image, voice_text } to the backend      │
│  - renders agent progress from the WebSocket       │
└───────────────┬────────────────────────────────────┘
                │  POST /ingest
┌───────────────▼────────────────────────────────────┐
│  LAYER 2: The Backend (Railway, FastAPI)           │
│  - ReAct agent loop (THINK → ACT → OBSERVE)        │
│  - routes each tool by TOOL_REGISTRY "runs_on":    │
│      google_api    → google_tools.py               │
│      cloud_browser → browser_tools.py (Browserbase)│
│      ios_native    → tools.py (phone URL schemes)  │
│  - gates tools on connected accounts               │
│  - broadcasts events over /ws                      │
└───────┬───────────────────────┬────────────────────┘
        │                       │
┌───────▼─────────┐   ┌─────────▼──────────────────────┐
│ LAYER 3a: Google │   │ LAYER 3b: Browserbase cloud    │
│  Docs/Sheets/    │   │  browser (signed in via cookies│
│  Gmail/Calendar/ │   │  synced from the Chrome ext.)  │
│  Tasks/People/   │   │  + web search/fetch/research   │
│  Drive           │   │                                │
└──────────────────┘   └────────────────────────────────┘
```

### Repo layout

```
backend/           FastAPI server — all AI + tool logic
  agent.py         ReAct agent + tool routing
  tools.py         registry + web.* + ios.* tools
  google_tools.py  Google API tools
  google_oauth.py  per-user Google OAuth token store
  browser_tools.py Browserbase cloud-browser tools
  cloud_browser.py Browserbase context + cookie injection
  connections.py   connected-services store
ios/               SwiftUI iPhone app — input layer only
chrome-extension/  Connect-your-accounts browser extension
```

---

## Configuration

Backend env vars (Railway):

- `GROQ_API_KEY` — the only required AI key (Groq multimodal).
- `GROQ_MODEL` — optional; defaults to `qwen/qwen3.6-27b`.
- `BROWSERBASE_API_KEY`, `BROWSERBASE_PROJECT_ID` — cloud browser + cookie sync.
- `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` — for the Google-API tool
  layer's per-user OAuth token refresh.

> **Note on Google API access:** the Chrome extension currently syncs *cookies*,
> which power the Browserbase cloud browser. The Google **REST API** tools
> (Docs/Sheets/Gmail/…) additionally need OAuth tokens; until a Google OAuth consent
> flow populates `google_oauth`, those tools return a clean "connect Google" message
> rather than failing. The cloud-browser and web/iOS tools work today.

## API contracts

```
POST /ingest                 { session_id, image, voice_text }
GET  /history                last 50 actions
GET  /memory                 learned preferences
GET  /connect/status         connected services for the account
POST /connect/cookies/sync   receive synced cookies (Chrome extension)
GET  /health                 { status: "ok" }
WS   /ws                     real-time agent event stream
```
