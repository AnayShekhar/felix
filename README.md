# Lumis 

## What is Lumis?

Okay so basically Lumis is like a magic assistant that lives in your phone and your
computer at the same time. You point your phone's camera at something in real life
(like a whiteboard, a receipt, or some messy notes), you say what you want out loud,
and Lumis actually goes and does it on your Mac. For real. Not fake.

Here's the big idea: **the brain of Lumis is the backend.** The phone app is just
the eyes and ears. You could swap the phone for a website or some other device and
Lumis would still work, because all the smart stuff happens in one place. We think
that's pretty cool.

A normal app makes you type and tap. Lumis lets you just *show it* something and
*tell it* what to do, and then it turns real life into stuff happening on your
computer.

### A quick example

1. You open the Lumis app and point it at a receipt.
2. You say: **"Hey Lumis, add this to my expense spreadsheet."**
3. The phone sends the picture + your words to the backend.
4. The backend reads the receipt with AI, figures out the store, the date, and the
   price.
5. Apple Numbers opens on your Mac and the new expense gets added. Boom. Done.

---

## All the features

Here is literally everything Lumis can do right now.

### On the phone (the iOS app)
-  **Live camera** — there's a real camera viewfinder with little corner brackets
  so it feels like a real camera.
-  **"Hey Lumis" wake word** — it's always quietly listening. When you say
  "Hey Lumis" it wakes up. It even understands when your phone mishears you a little
  (like "hey felics" or "hey phoenix") so it still works.
-  **Live transcription** — once it's awake it shows "Listening…" and writes out
  what you're saying on the screen in real time.
- **Manual capture button** — when you're done talking, you tap the big shutter
  button and THAT'S when it sends everything. Nothing gets sent by accident.
- **Live / Offline status** — a little dot at the top tells you if the phone is
  connected to the backend.
- **Result popup** — when Lumis finishes a job, a little card slides up telling
  you what it did, and sometimes a button to open the result (like a link to your
  new slideshow).

### What Lumis can actually DO (the tools)
The backend has **50 real tools** now. These aren't pretend — they actually control
your Mac (and your phone). They're grouped into families:

| Family | Tools |
|---|---|
| **Notes** | Make a note from an image, append to an existing note, list your notes. |
| **Numbers** | Make a new spreadsheet, add a receipt to your running expense file, read a sheet, edit a single cell. |
| **Slides** | Make a REAL Google Slides deck with titles + bullets and open it. |
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
- **Chaining steps** — Lumis can do more than one thing in a row. Like "make a
  slideshow and then email the link to my friend." The second step can use the
  result of the first step.
- **Anti-hallucination** — sometimes AI makes stuff up. We told it very firmly to
  ONLY use what it actually sees in the picture and to never invent fake prices or
  fake store names. If it can't read something, it leaves it blank instead of lying.
- *Intent locking** — the AI sometimes gets confused and wants to make a note for
  everything. So if you clearly say "email" or "spreadsheet," the backend forces it
  to do that thing instead of being lazy and making a note.
- **Persistent memory** — Lumis learns durable preferences from what you do (your
  expense file, your music service, who you email most, your preferred calendar) and
  quietly fills those in as defaults next time.
- **Conversation memory** — it remembers the last few turns in a session, so
  follow-ups like "do that again" or "change the time to 3pm" actually work.
- **Talks back** — Lumis reads results aloud on the phone (text-to-speech), and your
  commands are transcribed with **Groq Whisper** so names and tricky words come
  through right (it falls back to Apple's on-device speech if Whisper isn't set up).

---

## How it's built (the technical part)

Lumis has **3 layers.** Think of it like a sandwich.

```
┌─────────────────────────────────────────────────┐
│  LAYER 1: The Frontend (the phone / the website)  │
│  - takes a picture                                │
│  - listens to your voice                          │
│  - sends it off                                   │
│  - shows you the result                           │
└───────────────────────┬───────────────────────────┘
                         │  (sends image + text over the internet)
                         ▼
┌─────────────────────────────────────────────────┐
│  LAYER 2: The Backend (the brain) 🧠             │
│  - gets the image + voice                         │
│  - asks the AI what to do                         │
│  - runs the real actions on the Mac               │
│  - tells everybody what happened                  │
└───────────────────────┬───────────────────────────┘
                         │  (asks for a plan)
                         ▼
┌─────────────────────────────────────────────────┐
│  LAYER 3: The AI (Groq llama-4-scout) 🤖         │
│  - looks at the picture                           │
│  - reads your command                             │
│  - writes a step-by-step plan in JSON             │
└─────────────────────────────────────────────────┘
```

### Layer 1: The Frontend (iOS app)
This is written in **Swift** using **SwiftUI** (that's Apple's way of building app
screens). Here are the important files and what they do:

| File | What it does |
|---|---|
| `ContentView.swift` | The whole screen — camera, the status chip, the shutter button, the result popup. |
| `CameraManager.swift` | Runs the camera using **AVFoundation** and takes a full-quality photo when you tap capture. |
| `SpeechRecognizer.swift` | Listens with Apple's **Speech** framework, waits for "Hey Lumis," and writes down what you say. |
| `APIClient.swift` | Takes the photo, squishes it into a JPEG, turns it into text (base64), and sends it to the backend's `/ingest`. |
| `WebSocketClient.swift` | Keeps a live connection open to the backend so results show up instantly. If it drops, it reconnects by itself. |
| `Config.swift` | Where you put the backend's web address. |
| `Models.swift` | The shapes of the data going in and out. |

**How the voice part works (this part is tricky):** The mic stays on the whole time.
Apple's on-device speech recognizer listens for the wake words **"hey lumis"** (it
only has to nail two words, so it's reliable). Once it's awake, the audio of your
actual command is recorded and sent to **Groq Whisper**, which transcribes it far
more accurately — important for names like "Anay Shekhar" that Apple's recognizer
mangles. If Whisper isn't configured or fails, it silently falls back to Apple's
transcription. When you stop talking for about 1.3 seconds it "settles" — your words
stay on screen and wait for you to tap capture. A little **generation counter** makes
sure old, cancelled listening sessions don't clobber new ones (a real bug we had to
squash — without it, it only worked the first time!).

### Layer 2: The Backend (the brain)
This is written in **Python** using **FastAPI** (a fast web server) and runs with
**uvicorn**. Here's the file breakdown:

| File | What it does |
|---|---|
| `main.py` | Starts the server and sets up the WebSocket. |
| `routes.py` | The `/ingest` door where the phone drops off its image + voice. |
| `llm.py` | The planner. Sends your stuff to the AI and gets back a plan. |
| `engine.py` | The worker. Runs each step of the plan in order. |
| `tools.py` | The actual real-life actions (Notes, Numbers, Gmail, media, browser, iOS, etc). |
| `websocket.py` | Keeps track of everybody connected and tells them all the news. |
| `google_svc.py` | Logs into Google so it can make real Slides. |
| `memory.py` | Learns durable preferences (expense file, music service, …) and injects them into every plan. |
| `db.py` | SQLite action history so you can see and undo what Lumis did. |
| `tasks.py` | Background worker for long-running jobs. |

**The pipeline (step by step):**
1. The phone POSTs to `/ingest` with the image and voice text.
2. `llm.py` sends that to the AI and gets back a JSON plan that looks like a list of
   steps.
3. `engine.py` runs each step one at a time. Because controlling the Mac is slow, it
   runs each tool in a separate thread so the WebSocket doesn't freeze.
4. As each step finishes, the backend **broadcasts** the result to every connected
   phone/website over the WebSocket. That's why the result shows up live.

**How it controls the Mac:** the tools use a thing called **AppleScript** (with a
command called `osascript`) and the `open` command. So when Lumis "makes a note," it
literally tells the Notes app "hey, make a note with this text" the same way a human
would, just automatic.

### Layer 3: The AI (the planner's brain)
The backend doesn't decide things by itself, it asks an AI model. Lumis uses **one
provider only: Groq**, running `llama-4-scout` (it's multimodal — text *and* vision —
and super fast). `GROQ_API_KEY` is the only key you need. No Gemini, no OpenAI.

If Groq is totally unreachable, there's a **keyword fallback**: the backend just
looks for words like "email" or "spreadsheet" or "play X on spotify" and routes to
the right tool. Not as smart, but it still works offline-ish.

The AI is given a big set of instructions (called the **system prompt**) that tells
it: only output JSON, never write a paragraph, read images word-for-word, and don't
make stuff up. The JSON it sends back looks like this:

```json
{
  "steps": [
    { "tool": "gmail.draft_email", "args": { "to": "sam@example.com", "subject": "Hi", "body": "..." } }
  ]
}
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

`status` is usually `"success"` or `"error"`. There's also a special
`"ios_action"` status: the tool returns a phone-side URL scheme in `url` (with an
optional `fallback_url`), and the iOS app opens it directly with
`UIApplication.shared.open` — that's how "remind me on my phone" or "text Sarah"
happen natively on the iPhone. Content tools also include a longer `summary` field
for the on-screen sheet.

---

## The tech stack (all the tools we used)

- **Swift + SwiftUI** — the iPhone app (+ a SwiftUI menu-bar app for the Mac)
- **AVFoundation** — the camera
- **Speech framework** — wake-word ("Hey Lumis") detection on-device
- **Groq Whisper** — transcribes your actual command for accuracy on names
- **Python + FastAPI + uvicorn** — the backend server
- **WebSockets** — live updates so results pop up instantly
- **Groq (llama-4-scout)** — the one and only AI brain (text + vision)
- **Google Slides API** — for making real presentations
- **AppleScript (`osascript`)** — for controlling Mac apps
- **Railway** — hosts the backend at a permanent public URL (no tunnel needed);
  ngrok is just for local development

---

## How to run the whole thing

### The easy way (production): Railway
The backend is deployed on **Railway**, so it already has a permanent public URL —
no tunnel, no same-WiFi requirement. The iOS and Mac apps point at it by default.
Full steps are in [`DEPLOY.md`](DEPLOY.md); the short version:

1. Push the repo to GitHub → new Railway project → deploy from repo, root dir `backend`.
2. Set env vars: `GROQ_API_KEY` and `GROQ_MODEL`.
3. Copy the generated URL and drop it into the apps (see DEPLOY.md).
4. Verify: `curl https://<your-url>/health` → `{"status":"ok"}`.

Then just open the Xcode project in `ios/LumisApp/`, plug in your iPhone, and Run.
(Use a real phone, not the simulator, so the camera and mic actually work.)

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
app's Settings tab (or onboarding screen). The iOS app can also auto-discover a Mac
running the backend on the same WiFi. Check `https://<url>/health` → `{"status":"ok"}`.

### Setting up the AI key
In `backend/.env` (see `backend/.env.example`) you put your one secret key:
```
GROQ_API_KEY=your_key_here
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
```
Groq is the only provider — `GROQ_API_KEY` is all you need. The same key powers both
the planner (llama-4-scout) and voice transcription (Whisper).

---

## Why this is actually a cool idea

Most apps make you do all the work — type the email, open the spreadsheet, copy the
numbers. Lumis flips it around. You just show it the real world and talk like a
normal human, and it turns that into real actions across a bunch of different apps.
The phone, the website, whatever — they're all just different faces for the same
smart backend. That's the whole point: **reality goes in, finished work comes out.**
