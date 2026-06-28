# Lumis

## What is Lumis?

Okay so basically Lumis is like a magic assistant that lives in your phone and your
computer at the same time. You point your phone's camera at something in real life
(like a whiteboard, a receipt, or some messy notes), you say what you want out loud,
and Lumis actually goes and does it on your Mac. For real. Not fake.

Here's the big idea: **the brain of Lumis is the backend.** The phone app is the
eyes and ears, and your Mac is the hands. You could swap the phone for a website or
some other device and Lumis would still work, because all the smart stuff happens in
one place. We think that's pretty cool.

A normal app makes you type and tap. Lumis lets you just *show it* something and
*tell it* what to do, and then it turns real life into stuff happening on your
computer.

### A quick example

1. You open the Lumis app and point it at a receipt.
2. You say: **"Hey Lumis, add this to my expense spreadsheet."**
3. The phone sends the picture + your words to the backend.
4. The backend reads the receipt with AI, figures out the store, the date, and the
   price.
5. The plan gets sent to your Mac, Apple Numbers opens, and the new expense gets
   added. Boom. Done.

---

## The three pieces (brain / eyes / hands)

Lumis is really one assistant wearing three hats. This is the single most important
thing to understand about how it's built:

- **The brain 🧠 — the backend on Railway.** It gets the picture + voice, asks the
  AI for a plan, remembers your preferences, and decides what to do. It lives at a
  permanent public URL in the cloud.
- **The eyes & ears 👀 — the iPhone app.** Camera + microphone + the chat screen.
  It captures the real world and shows you results. It never makes decisions.
- **The hands ✋ — the Mac menu-bar app (and its local agent).** Railway runs in
  Linux and *can't* run `osascript` or control Mac apps, so anything that touches
  your actual Mac (Notes, Numbers, Finder, volume, screenshots) is handed down to a
  small agent running on your Mac, which does it locally and reports back.

So a single command can travel **phone → cloud brain → your Mac → back to the
phone**, live, in a couple of seconds.

---

## Accounts & pairing (new)

Lumis is now account-based, so your phone and your Mac share one brain and one
memory.

- **Sign in.** Both the iPhone app and the Mac app have a real login: email +
  password, **Sign in with Apple**, or **Sign in with Google**. Sessions are JWTs
  that last 30 days; passwords are hashed with PBKDF2. On iOS the token is stored in
  the Keychain.
- **One phone ↔ one Mac, paired by a 6-digit code.** Open the Mac app, it shows a
  short numeric code; type that code into the iPhone, and the two are linked to your
  account. After that, what you say on the phone runs on *your* Mac.
- **Honest online/offline status.** The Mac sends a heartbeat every few seconds. The
  phone only shows "online" if it has heard from your Mac in the last 30 seconds —
  no fake green dots.
- **Per-account memory.** Everything Lumis learns (your expense file, your music
  service, who you email most) is scoped to your account, so the phone and the Mac
  see the same memory.

---

## All the features

Here is basically everything Lumis can do right now.

### On the phone (the iOS app)
- **Account login** — email/password, Sign in with Apple, or Google. A splash screen
  validates your saved session on launch.
- **Home + glass chat bar** — the main screen is a clean "Parchment" home with a
  frosted **Liquid Glass** chat bar pinned to the bottom. You can type a command, or
  tap the camera button to capture the real world.
- **Slide-out sidebar** — a hamburger menu opens a sidebar for history, memory,
  settings, and pairing.
- **Live camera capture** — a real camera viewfinder with corner brackets. You frame
  the thing, tap the shutter, and *that's* when it sends. Nothing goes by accident.
- **"Hey Lumis" wake word** — it's always quietly listening. When you say
  "Hey Lumis" it wakes up. It even forgives mishears ("hey felics", "hey phoenix").
- **Live transcription** — once awake it shows "Listening…" and writes out what
  you're saying in real time.
- **Result popup** — when Lumis finishes, a card slides up telling you what it did,
  sometimes with a button to open the result (a link to your draft email, etc.).
- **Talks back** — results are read aloud with text-to-speech.
- **Native phone actions** — some commands open things directly on the iPhone
  (Reminders, Notes, Maps, Messages drafts) via URL schemes.

### On the Mac (the menu-bar app)
- **Lives in the menu bar** (`LSUIElement`), out of your way.
- **Login + pairing** — sign into your account and show the 6-digit code the phone
  uses to pair.
- **Dashboard / activity feed** — a live feed of everything Lumis is doing, with
  expandable cards for content results (calendar reads, research, screen captures).
- **Auto-starts the local agent** — the app runs `mac_agent.py` for you and shows
  **"Mac Agent: Connected / Offline"** in the popover, so the brain always has hands.
- **Memory view** — see and delete the preferences Lumis has learned.

### What Lumis can actually DO (the tools)
The backend has **50 real tools**. These aren't pretend — they actually control your
Mac (and your phone). They're grouped into families:

| Family | Tools |
|---|---|
| **Notes** | Make a note from an image, append to an existing note, list your notes. |
| **Numbers** | Make a new spreadsheet, add a receipt to your running expense file, read a sheet, edit a single cell. |
| **Gmail** | Draft an email, read your inbox, read a specific email, open a pre-filled reply. |
| **Browser (Chrome)** | Open a URL, read the current page's text, fill in a form. |
| **Media** | Play/pause, next/previous track, open Spotify (and play), open Apple Music. |
| **Calendar** | Create an event, read today / this week, find free time. |
| **Reminders** | Add, read, and complete reminders. |
| **Contacts** | Look up someone's name / email / phone. |
| **System** | Volume, brightness, lock screen, empty trash, battery, open Focus settings. |
| **Finder** | Find / open / move / rename files, create folders, reveal in Finder. |
| **Clipboard** | Copy text to the clipboard. |
| **Screen** | Screenshot the Mac and describe it, or act on what it sees (Groq vision). |
| **Web** | Search, fetch a page, or run a full research agent that searches + synthesizes + saves a note. |
| **iPhone (native)** | Create a reminder/note on the phone, open Maps, or draft a Message — the backend hands the phone a URL scheme to open. |

Anything that can't be undone (sending a reply, filling a form, moving a file,
drafting a message, creating an event) is marked **irreversible** so it can be gated
behind a confirmation.

### Smart stuff happening behind the scenes
- **It actually thinks in a loop (ReAct).** Lumis doesn't guess a whole plan up
  front. It does ONE thing, looks at the real result, and then decides the next
  thing based on what actually happened — THINK → ACT → OBSERVE → repeat. So if a
  step fails, it can notice and try a different approach instead of barreling ahead.
- **It can look at your Mac to check its work.** Mid-task, the agent can take a
  screenshot and *see* the screen (Groq vision) to confirm something worked before
  moving on.
- **It can ask you a question.** If it genuinely can't tell what you mean ("which
  Sarah?"), it pauses and asks. You just answer (capture again and say it) and it
  picks up right where it left off, with full memory of the conversation.
- **Chaining steps** — Lumis can do several things in a row. Like "make a note of
  this receipt and remind me to submit expenses Friday." Each step can use the
  result of the one before it.
- **Anti-hallucination** — sometimes AI makes stuff up. We told it very firmly to
  ONLY use what it actually sees in the picture and to never invent fake prices or
  fake store names. If it can't read something, it leaves it blank instead of lying.
- **Persistent memory** — Lumis learns durable preferences from what you do (your
  expense file, your music service, who you email most, your preferred calendar) and
  quietly fills those in as defaults next time. Memory is per-account.
- **Conversation memory** — it remembers the last few turns in a session, so
  follow-ups like "do that again" or "change the time to 3pm" actually work.
- **Talks back** — Lumis reads results aloud on the phone (text-to-speech), and your
  commands are transcribed with **Groq Whisper** so names and tricky words come
  through right (it falls back to Apple's on-device speech if Whisper isn't set up).

---

## How it's built (the technical part)

Lumis has **3 layers,** plus the Mac agent that gives the cloud brain a pair of
local hands.

```
┌─────────────────────────────────────────────────┐
│  LAYER 1: The Frontend (iPhone / Mac menu bar)    │
│  - takes a picture / hears your voice             │
│  - sends it off (authenticated)                   │
│  - shows you the result live                      │
└───────────────────────┬───────────────────────────┘
                        │  image + text over the internet
                        ▼
┌─────────────────────────────────────────────────┐
│  LAYER 2: The Backend (the brain) 🧠  [Railway]  │
│  - gets the image + voice                         │
│  - asks the AI what to do                         │
│  - runs cloud tools itself                        │
│  - hands Mac-only tools to the local agent ───────┼──┐
│  - broadcasts results to everybody                │  │
└───────────────────────┬───────────────────────────┘  │
                        │  asks for a plan              │  execute_on_mac
                        ▼                               ▼
┌──────────────────────────────────┐   ┌──────────────────────────────┐
│  LAYER 3: The AI (llama-4-scout)  │   │  Mac agent ✋ (your Mac)      │
│  - looks at the picture           │   │  - runs osascript / open      │
│  - reads your command             │   │  - controls Notes, Numbers…   │
│  - writes a step plan in JSON     │   │  - replies mac_result         │
└──────────────────────────────────┘   └──────────────────────────────┘
```

### Layer 1a: The iPhone app
Written in **Swift / SwiftUI** (iOS 17+). Important files:

| File | What it does |
|---|---|
| `UI/RootView.swift` | Top-level gate: splash → auth flow → main app, based on login state. |
| `UI/MainTabView.swift` | The shell — home, glass chat bar, slide-out sidebar, camera sheet. |
| `UI/ChatBarView.swift` | The frosted Liquid Glass chat bar at the bottom. |
| `UI/SidebarView.swift` | History, memory, settings, pairing. |
| `Auth/…` | Login/sign-up, Sign in with Apple, Google, Keychain storage. |
| `CameraManager.swift` | Runs the camera with **AVFoundation**, takes a full-quality photo. |
| `SpeechRecognizer.swift` | Apple **Speech** framework — wake word + live transcript. |
| `WhisperTranscriber.swift` | Sends the command audio to **Groq Whisper** for accuracy. |
| `APIClient.swift` | Encodes the photo to base64 and POSTs it to `/ingest`. |
| `WebSocketClient.swift` | Live connection to the backend; auto-reconnects on drop. |
| `MacDiscovery.swift` | Finds a Mac running the backend on the same WiFi (local dev). |
| `DeepLinkRouter.swift` | Opens native phone URL schemes for `ios_action` results. |

**How the voice part works (this part is tricky):** the mic stays on the whole time.
Apple's on-device recognizer only has to nail two words — **"hey lumis"** — so it's
reliable. Once awake, the audio of your actual command goes to **Groq Whisper**,
which transcribes it far more accurately (important for names like "Anay Shekhar"
that Apple mangles). If Whisper isn't configured, it silently falls back to Apple.
When you stop talking for ~1.3s it "settles" and waits for you to tap capture. A
**generation counter** keeps old, cancelled listening sessions from clobbering new
ones (a real bug — without it, it only worked the first time!).

### Layer 1b: The Mac menu-bar app
Also **SwiftUI**, runs as a menu-bar-only app. Important files:

| File | What it does |
|---|---|
| `LumisApp.swift` | App entry, menu-bar item, popover. |
| `LoginView.swift` / `AuthStore.swift` | Account login (email, Apple, Google). |
| `LinkController.swift` / `LinkCodeView.swift` | Shows the 6-digit pairing code. |
| `MacAgentController.swift` | Auto-starts and supervises the local `mac_agent.py`. |
| `DashboardView.swift` / `EventFeedView.swift` | The live activity feed. |
| `MemoryView.swift` | View/delete learned preferences. |
| `APIService.swift` | Talks to the backend (auth, status, memory). |

### Layer 2: The Backend (the brain)
**Python + FastAPI + uvicorn**, **SQLite** for persistence, deployed on **Railway**.

| File | What it does |
|---|---|
| `main.py` | Starts the server and the `/ws` WebSocket. |
| `routes.py` | `/ingest` (image + voice in), history, undo, memory, `/mac/status`, health. |
| `auth.py` | Accounts: register/login, Apple + Google verification, JWT sessions. |
| `linking.py` | Mac↔phone pairing: generate code, pair, heartbeat, online status. |
| `agent.py` | The **ReAct agent** — the THINK→ACT→OBSERVE loop that decides one tool at a time. |
| `agent_prompt.py` | The agent's system prompt (its rules + the full tool catalog). |
| `tools.py` | The 50 real actions (Notes, Numbers, Gmail, media, browser, iOS, …). |
| `mac_bridge.py` | Sends one tool to the Mac agent over `/ws` and awaits the result. |
| `vision.py` | Grabs a Mac screenshot so the agent can *see* the screen. |
| `mac_agent.py` | Runs on your Mac; executes Mac-only tools and replies over `/ws`. |
| `websocket.py` | Tracks everyone connected (input clients + the Mac agent) and broadcasts. |
| `memory.py` | Learns per-account preferences and feeds them to the agent. |
| `db.py` | SQLite: action history, users, pairings. |
| `tasks.py` | Background worker that runs long jobs on the same agent. |

**The pipeline (step by step):**
1. The phone POSTs to `/ingest` with the image, voice text, and its auth token.
   The backend returns immediately — results stream back over the WebSocket.
2. `agent.py` starts a **reasoning loop** on Groq. Each turn the model returns ONE
   JSON action: call a tool, look at the Mac screen, ask you a question, or finish.
3. For a tool call, the agent decides **where** it runs and then **reads the real
   result before deciding the next step**:
   - **Cloud tools** (`ios.*`, `web.search`, `web.fetch_page`) run on Railway.
   - **Everything else** goes to your Mac via `mac_bridge` as `execute_on_mac`
     `{action_id, tool, args}`; it waits (up to 30s) for the agent's `mac_result`.
4. Every step is **broadcast** to every connected phone/Mac over the WebSocket, so
   results show up live. The loop keeps going until the agent says it's done (or
   hits its step limit). If it needs a detail, it pauses and asks; you answer and it
   resumes with full context.

**How it controls the Mac:** the Mac agent uses **AppleScript** (`osascript`) and
the `open` command. So when Lumis "makes a note," it literally tells the Notes app
"hey, make a note with this text," the same way a human would — just automatic. If no
agent is connected, a Mac step returns *"Mac agent not connected."*

### Layer 3: The AI (the agent's brain)
Lumis uses **one provider only: Groq**, running `llama-4-scout` (multimodal — text
*and* vision — and super fast). `GROQ_API_KEY` is the only key you need. No Gemini,
no OpenAI.

The AI gets a big **system prompt** (`agent_prompt.py`): only output JSON, read
images word-for-word, don't make stuff up, and emit exactly ONE action per turn.
Instead of one big plan, each turn is a single decision the loop acts on and then
feeds the real result back. The JSON is one of four shapes:

```json
{ "action": "tool_call", "tool": "gmail.draft_email",
  "args": { "to": "sam@example.com", "subject": "Hi", "body": "..." },
  "reasoning": "…", "status_message": "Opening a draft…" }
```
```json
{ "action": "capture_screen", "reasoning": "Check the draft actually opened" }
```
```json
{ "action": "ask_user", "question": "Which Sarah — Sarah Lee or Sarah Kim?" }
```
```json
{ "action": "finish", "title": "Draft ready", "summary": "Opened a draft to Sam.",
  "speak": "Your draft to Sam is ready." }
```

---

## The data contracts (what the messages look like)

**Phone → Backend** (when you tap capture):
```json
{
  "session_id": "ios-abc123",
  "image": "<the photo as a long base64 string>",
  "voice_text": "draft an email to my boss",
  "timestamp": 1718380800
}
```

**Backend → Phone** (live, over the WebSocket):
```json
{
  "session_id": "ios-abc123",
  "event": "step_executed",
  "data": {
    "tool": "gmail.draft_email",
    "status": "success",
    "title": "New Draft",
    "message": "Opened a Gmail draft in Chrome.",
    "url": "https://mail.google.com/...",
    "speak": "Opened a draft for you."
  }
}
```

**Backend → Mac agent** (when a step has to run locally):
```json
{ "event": "execute_on_mac", "action_id": "a-42", "tool": "notes.create_from_image", "args": { "text": "..." } }
```
…and the agent replies `{ "event": "mac_result", "action_id": "a-42", "result": { ... } }`.

`status` is usually `"success"` or `"error"`. There's also a special
`"ios_action"` status: the tool returns a phone-side URL scheme in `url` (with an
optional `fallback_url`), and the iOS app opens it directly with
`UIApplication.shared.open` — that's how "remind me on my phone" or "text Sarah"
happen natively. Content tools also include a longer `summary` field for the
on-screen sheet and the Mac dashboard card.

---

## The tech stack (all the tools we used)

- **Swift + SwiftUI** — the iPhone app *and* the Mac menu-bar app
- **AVFoundation** — the camera
- **Speech framework** — wake-word ("Hey Lumis") detection on-device
- **Groq Whisper** — transcribes your actual command for accuracy on names
- **Python + FastAPI + uvicorn** — the backend server
- **SQLite** — accounts, pairings, and action history
- **WebSockets** — live updates *and* the cloud↔Mac-agent bridge
- **Groq (llama-4-scout)** — the one and only AI brain (text + vision), driving the ReAct agent loop
- **AppleScript (`osascript`)** — for controlling Mac apps (via the Mac agent)
- **Sign in with Apple / Google** — account auth
- **Railway** — hosts the backend at a permanent public URL (no tunnel needed);
  ngrok is just for local development

---

## How to run the whole thing

### The easy way (production): Railway
The backend is deployed on **Railway**, so it already has a permanent public URL —
no tunnel, no same-WiFi requirement. The iOS and Mac apps point at it by default.
Full steps are in [`DEPLOY.md`](DEPLOY.md); the short version:

1. Push the repo to GitHub → new Railway project → deploy from repo, root dir `backend`.
2. Set env vars: `GROQ_API_KEY`, `GROQ_MODEL`, and `LUMIS_JWT_SECRET` (plus optional
   `LUMIS_GOOGLE_CLIENT_ID` / `LUMIS_APPLE_BUNDLE_ID` for social login).
3. Copy the generated URL and drop it into the apps (see DEPLOY.md).
4. Verify: `curl https://<your-url>/health` → `{"status":"ok"}`.

Then:
- Open `ios/LumisApp/` in Xcode, plug in a **real iPhone** (not the simulator, so the
  camera and mic work), and Run. Sign in.
- Open `macos-app/Lumis/` in Xcode and Run the Mac app. Sign into the **same
  account**. It shows a 6-digit code — type that into the phone to pair. The Mac app
  auto-starts the local agent so the brain has hands.

### The local-dev way
**1. Start the backend** (the brain):
```bash
cd backend
./venv/bin/uvicorn main:app --reload --reload-dir . --reload-exclude 'venv' --port 8000
```

**2. (Optional) Expose it** so the phone can reach your Mac during development:
```bash
ngrok http 8000
```
Ngrok prints a public URL like `https://something.ngrok-free.dev`. Put it in the
app's Settings (or onboarding). The iOS app can also auto-discover a Mac running the
backend on the same WiFi. Check `https://<url>/health` → `{"status":"ok"}`.

**3. Run the Mac agent** (the hands) — the Mac app does this for you, or manually:
```bash
cd backend && LUMIS_BACKEND_URL=https://<your-url> ./run_mac_agent.sh
```
Check `GET /mac/status` to confirm it's connected.

### Setting up the AI key
In `backend/.env` (see `backend/.env.example`):
```
GROQ_API_KEY=your_key_here
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
LUMIS_JWT_SECRET=some-long-random-string
```
Groq is the only AI provider — `GROQ_API_KEY` powers both the agent
(llama-4-scout) and voice transcription (Whisper). Optional: `AGENT_MAX_STEPS`
(default 20) caps how many tool calls the reasoning loop will take.

---

## Why this is actually a cool idea

Most apps make you do all the work — type the email, open the spreadsheet, copy the
numbers. Lumis flips it around. You just show it the real world and talk like a
normal human, and it turns that into real actions across a bunch of different apps.
The phone, the Mac, a website — they're all just different faces (and hands) for the
same smart backend. That's the whole point: **reality goes in, finished work comes
out.**
