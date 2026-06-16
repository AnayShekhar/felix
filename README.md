# Felix 

## What is Felix?

Okay so basically Felix is like a magic assistant that lives in your phone and your
computer at the same time. You point your phone's camera at something in real life
(like a whiteboard, a receipt, or some messy notes), you say what you want out loud,
and Felix actually goes and does it on your Mac. For real. Not fake.

Here's the big idea: **the brain of Felix is the backend.** The phone app is just
the eyes and ears. You could swap the phone for a website or some other device and
Felix would still work, because all the smart stuff happens in one place. We think
that's pretty cool.

A normal app makes you type and tap. Felix lets you just *show it* something and
*tell it* what to do, and then it turns real life into stuff happening on your
computer.

### A quick example

1. You open the Felix app and point it at a receipt.
2. You say: **"Hey Felix, add this to my expense spreadsheet."**
3. The phone sends the picture + your words to the backend.
4. The backend reads the receipt with AI, figures out the store, the date, and the
   price.
5. Apple Numbers opens on your Mac and the new expense gets added. Boom. Done.

---

## All the features

Here is literally everything Felix can do right now.

### On the phone (the iOS app)
-  **Live camera** — there's a real camera viewfinder with little corner brackets
  so it feels like a real camera.
-  **"Hey Felix" wake word** — it's always quietly listening. When you say
  "Hey Felix" it wakes up. It even understands when your phone mishears you a little
  (like "hey felics" or "hey phoenix") so it still works.
-  **Live transcription** — once it's awake it shows "Listening…" and writes out
  what you're saying on the screen in real time.
- **Manual capture button** — when you're done talking, you tap the big shutter
  button and THAT'S when it sends everything. Nothing gets sent by accident.
- **Live / Offline status** — a little dot at the top tells you if the phone is
  connected to the backend.
- **Result popup** — when Felix finishes a job, a little card slides up telling
  you what it did, and sometimes a button to open the result (like a link to your
  new slideshow).

### What Felix can actually DO (the tools)
The backend can do 7 real actions. These aren't pretend, they actually control your
Mac:

| Tool | What it does |
|---|---|
| **Apple Notes** | Reads text from your image and makes a new note. |
| **Apple Numbers (new sheet)** | Makes a brand new spreadsheet from your stuff. |
| **Apple Numbers (expenses)** | Adds a receipt to ONE expense file that keeps growing every time. |
| **Gmail draft** | Opens Gmail in Chrome with the email already written (it does NOT send it, just writes it). |
| **Google Slides** | Makes a REAL Google Slides presentation with title + bullet points, and opens it. |
| **Spotify** | Searches a song and plays it. |
| **Chrome** | Opens any website. |

### Smart stuff happening behind the scenes
- **Chaining steps** — Felix can do more than one thing in a row. Like "make a
  slideshow and then email the link to my friend." The second step can use the
  result of the first step.
- **Anti-hallucination** — sometimes AI makes stuff up. We told it very firmly to
  ONLY use what it actually sees in the picture and to never invent fake prices or
  fake store names. If it can't read something, it leaves it blank instead of lying.
- *Intent locking** — the AI sometimes gets confused and wants to make a note for
  everything. So if you clearly say "email" or "spreadsheet," the backend forces it
  to do that thing instead of being lazy and making a note.

---

## How it's built (the technical part)

Felix has **3 layers.** Think of it like a sandwich.

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
│  LAYER 3: The AI (Gemini or Groq) 🤖              │
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
| `SpeechRecognizer.swift` | Listens with Apple's **Speech** framework, waits for "Hey Felix," and writes down what you say. |
| `APIClient.swift` | Takes the photo, squishes it into a JPEG, turns it into text (base64), and sends it to the backend's `/ingest`. |
| `WebSocketClient.swift` | Keeps a live connection open to the backend so results show up instantly. If it drops, it reconnects by itself. |
| `Config.swift` | Where you put the backend's web address. |
| `Models.swift` | The shapes of the data going in and out. |

**How the voice part works (this part is tricky):** The mic stays on the whole time.
Apple's speech recognizer turns your audio into text constantly. The code looks for
the words "hey felix" inside that text, and grabs whatever you say *after* it as your
command. When you stop talking for about 1.3 seconds, it "settles" — it keeps your
words on screen and waits for you to tap capture. There's a little number called a
**generation counter** that makes sure old, cancelled listening sessions don't mess
up the new ones (this was a real bug we had to squash — without it, it only worked
the first time!).

### Layer 2: The Backend (the brain)
This is written in **Python** using **FastAPI** (a fast web server) and runs with
**uvicorn**. Here's the file breakdown:

| File | What it does |
|---|---|
| `main.py` | Starts the server and sets up the WebSocket. |
| `routes.py` | The `/ingest` door where the phone drops off its image + voice. |
| `llm.py` | The planner. Sends your stuff to the AI and gets back a plan. |
| `engine.py` | The worker. Runs each step of the plan in order. |
| `tools.py` | The actual real-life actions (Notes, Numbers, Gmail, etc). |
| `websocket.py` | Keeps track of everybody connected and tells them all the news. |
| `google_svc.py` | Logs into Google so it can make real Slides. |

**The pipeline (step by step):**
1. The phone POSTs to `/ingest` with the image and voice text.
2. `llm.py` sends that to the AI and gets back a JSON plan that looks like a list of
   steps.
3. `engine.py` runs each step one at a time. Because controlling the Mac is slow, it
   runs each tool in a separate thread so the WebSocket doesn't freeze.
4. As each step finishes, the backend **broadcasts** the result to every connected
   phone/website over the WebSocket. That's why the result shows up live.

**How it controls the Mac:** the tools use a thing called **AppleScript** (with a
command called `osascript`) and the `open` command. So when Felix "makes a note," it
literally tells the Notes app "hey, make a note with this text" the same way a human
would, just automatic.

### Layer 3: The AI (the planner's brain)
The backend doesn't decide things by itself, it asks an AI model. It tries them in
this order:
1. **Google Gemini** (if there's a `GEMINI_API_KEY`) — it's really good at reading
   images.
2. **Groq** running `llama-4-scout` — this is the one we use right now. It can see
   images too and it's super fast.
3. **Keyword fallback** — if the AI is totally down, the backend just looks for
   words like "email" or "spreadsheet" and guesses. Not as smart but it still works.

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
    "status": "executed",
    "title": "New Draft",
    "message": "Opened a Gmail draft in Chrome.",
    "url": "https://mail.google.com/..."
  }
}
```

---

## The tech stack (all the tools we used)

- **Swift + SwiftUI** — the iPhone app
- **AVFoundation** — the camera
- **Speech framework** — turning your voice into text
- **Python + FastAPI + uvicorn** — the backend server
- **WebSockets** — live updates so results pop up instantly
- **Groq (llama-4-scout)** / **Google Gemini** — the AI brains
- **Google Slides API** — for making real presentations
- **AppleScript (`osascript`)** — for controlling Mac apps
- **ngrok** — a tunnel that gives the local backend a public web address so the phone
  can reach it from anywhere

---

## How to run the whole thing

You need 3 things running at once.

**1. Start the backend** (the brain):
```bash
cd backend
./venv/bin/uvicorn main:app --reload --reload-dir . --reload-exclude 'venv' --port 8000
```

**2. Start the tunnel** (so the phone can reach your Mac from the internet):
```bash
ngrok http 8000
```
Ngrok prints a public URL like `https://something.ngrok-free.dev`. Copy it into
`ios/FelixApp/FelixApp/Config.swift` (`baseURL`). If you have a reserved domain on
your ngrok account, use `ngrok http 8000 --url=your-domain.ngrok-free.dev` instead.

Check it's alive by going to `https://<your-ngrok-url>/health` — it should say
`{"status":"ok"}`.

**3. Run the iOS app:**
- Open the Xcode project in `ios/FelixApp/`.
- Make sure `ios/FelixApp/FelixApp/Config.swift` has the ngrok URL from step 2.
- Plug in your iPhone and hit Run. (Use a real phone, not the simulator, so the
  camera and mic actually work.)

### Setting up the AI keys
In `backend/.env` you put your secret keys:
```
GROQ_API_KEY=your_key_here
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
```
If you have a Gemini key, add `GEMINI_API_KEY=your_key` and Felix will use that
instead because it reads images even better.

---

## Why this is actually a cool idea

Most apps make you do all the work — type the email, open the spreadsheet, copy the
numbers. Felix flips it around. You just show it the real world and talk like a
normal human, and it turns that into real actions across a bunch of different apps.
The phone, the website, whatever — they're all just different faces for the same
smart backend. That's the whole point: **reality goes in, finished work comes out.**
