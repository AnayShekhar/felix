You are rebuilding Felix from its current MVP state into its full product vision. 

Here is the complete target spec:

What Felix Should Become
Felix is a voice-and-vision-first autonomous computing layer that sits above all your apps and devices. You speak or show it something, it understands intent, and it executes multi-step actions across your digital life. The phone is the most natural input device but not the only one. The Mac agent is the most powerful executor but not the only one. The brain is universal and lives in the cloud.

Core product in full
The brain is a persistent AI backend that maintains memory of who you are, how you work, what your files look like, who you email, what your calendar patterns are, and what actions you've taken before. Every command gets routed through this brain which decides what to do, in what order, on which device, and whether to ask for confirmation before acting. It should support multi-step autonomous task pipelines where Felix works in the background and reports back when done.
The iOS app is the primary input device. It has a live camera viewfinder for capturing physical world context, always-on wake word detection, real-time voice transcription, manual capture for when you want deliberate control, and a clean action history feed showing everything Felix has done across all your devices. It should also be able to act as a target device for phone-to-phone workflows within the limits Apple allows via Shortcuts and accessibility.
The Mac agent is a lightweight background process that requires zero interaction after first install. It receives action instructions from the brain and executes them with full system access. It should be able to control any app via Accessibility APIs, read screen content to inform decisions, manage files and folders, control the browser including opening tabs and filling forms, send and read emails, create and edit documents and spreadsheets, manage calendar events, control media playback, run terminal commands, and take screenshots to send back to the brain as context. Every action gets logged with a one-click undo.
The Windows agent is the same concept rebuilt for Windows using UIAutomation APIs. Lower priority but same interface contract as the Mac agent so the brain talks to both identically.
The web input client is a browser tab or Electron app that uses your webcam and microphone as the input layer for people who want to control their computer without picking up their phone. Same brain, different eyes and ears.

Competitive analysis
Siri, Google Assistant, Alexa
 These are the obvious comparisons people will make. They are fundamentally sandboxed — Apple and Google deliberately limit what they can touch on your device. Siri cannot open a specific file, write to a spreadsheet, or compose an email with content you dictated while pointing your camera at something. Felix has no such sandbox because your Mac agent runs with full system permissions. Felix wins on depth of action by a wide margin. They win on distribution and wake word reliability. Felix's real competition with them is on the iOS side where Apple's restrictions apply to Felix too.
Rabbit R1 and Humane AI Pin
 These are dedicated hardware devices trying to solve the same problem — a voice-and-vision assistant that acts on your behalf. Rabbit's LAM approach and Humane's projection interface both failed commercially because the hardware added friction instead of removing it. Felix's insight is better: you already have a great camera and mic in your pocket. No new hardware needed. Felix is what these products were trying to be but delivered through something you already carry.
Cursor and GitHub Copilot
 These are AI that controls one specific domain — your code editor. Felix is the same concept but for your entire computer. Developers already understand and pay for this category. A Felix that can code, run tests, read the output, and file a GitHub issue from a voice command is a direct competitor to Copilot for the parts of the workflow that live outside the editor.
Apple Intelligence and Windows Copilot
 These are the existential threat to watch. Apple Intelligence is being built deeply into the OS and will eventually do many of the things Felix does, but slowly, cautiously, and only within Apple's approved boundaries. Windows Copilot is similarly conservative. Neither will do truly autonomous multi-step actions or accept camera input from the physical world as a command trigger for years, if ever. Felix moves faster and goes deeper. The risk is that in three to five years the OS catches up. The window is now.
Alfred, Raycast, Keyboard Maestro
 These are power-user Mac automation tools with large loyal audiences. They are keyboard and menu driven — you still have to know the exact command or macro name. Felix replaces the need to remember commands with natural language. The people who use these tools are exactly the early adopters who will immediately understand and pay for Felix. These are not competitors, they are the audience.
Zapier and Make
 Workflow automation platforms that connect apps together with triggers and actions. They require significant setup, live in the browser, and have no vision input. Felix is what Zapier wishes it could be for individual users — instead of building a workflow in a UI you just say what you want done. Felix should be able to replace most personal Zapier workflows with a single voice command.

What Felix has that nobody else has
Physical world to digital action in a single gesture. You point your camera at something real — a receipt, a whiteboard, a business card, a printed document, a product on a shelf — say what you want done with it, and Felix handles the rest on your computer. No other product in this space has this combination. Siri can see photos after the fact. Rabbit tried hardware. Nobody has nailed the phone-as-contextual-camera-for-your-computer workflow that Felix is built around.
Cross-device action routing. Felix can receive input on one device and execute on another. That architecture is unique and defensible.

What to build in order
First, make the existing Mac experience bulletproof and fast. Latency and reliability are the product at this stage. If Felix takes four seconds to respond or gets the action wrong one in five times, nobody will use it daily.
Second, ship the action history and undo system. This is what makes people trust it with real work.
Third, build persistent memory so Felix learns your preferences over time and commands get shorter and smarter.
Fourth, ship the web input client so people can use Felix from their laptop without the phone.
Fifth, build multi-step autonomous tasks with a progress indicator so Felix can work in the background.
Sixth, ship Windows agent.
Seventh, open a developer SDK so others can build new action types and integrations.
The business model is a monthly subscription, around fifteen to twenty dollars for individuals and seat-based pricing for teams, with an enterprise tier that adds on-premise deployment, SSO, audit logs, and admin controls for companies that need data to stay local.



Here is the current codebase state:

Felix
What is Felix?
Okay so basically Felix is like a magic assistant that lives in your phone and your computer at the same time. You point your phone's camera at something in real life (like a whiteboard, a receipt, or some messy notes), you say what you want out loud, and Felix actually goes and does it on your Mac. For real. Not fake.

Here's the big idea: the brain of Felix is the backend. The phone app is just the eyes and ears. You could swap the phone for a website or some other device and Felix would still work, because all the smart stuff happens in one place. We think that's pretty cool.

A normal app makes you type and tap. Felix lets you just show it something and tell it what to do, and then it turns real life into stuff happening on your computer.

A quick example
You open the Felix app and point it at a receipt.
You say: "Hey Felix, add this to my expense spreadsheet."
The phone sends the picture + your words to the backend.
The backend reads the receipt with AI, figures out the store, the date, and the price.
Apple Numbers opens on your Mac and the new expense gets added. Boom. Done.
All the features
Here is literally everything Felix can do right now.

On the phone (the iOS app)
Live camera — there's a real camera viewfinder with little corner brackets so it feels like a real camera.
"Hey Felix" wake word — it's always quietly listening. When you say "Hey Felix" it wakes up. It even understands when your phone mishears you a little (like "hey felics" or "hey phoenix") so it still works.
Live transcription — once it's awake it shows "Listening…" and writes out what you're saying on the screen in real time.
Manual capture button — when you're done talking, you tap the big shutter button and THAT'S when it sends everything. Nothing gets sent by accident.
Live / Offline status — a little dot at the top tells you if the phone is connected to the backend.
Result popup — when Felix finishes a job, a little card slides up telling you what it did, and sometimes a button to open the result (like a link to your new slideshow).
What Felix can actually DO (the tools)
The backend can do 7 real actions. These aren't pretend, they actually control your Mac:

Tool	What it does
Apple Notes	Reads text from your image and makes a new note.
Apple Numbers (new sheet)	Makes a brand new spreadsheet from your stuff.
Apple Numbers (expenses)	Adds a receipt to ONE expense file that keeps growing every time.
Gmail draft	Opens Gmail in Chrome with the email already written (it does NOT send it, just writes it).
Google Slides	Makes a REAL Google Slides presentation with title + bullet points, and opens it.
Spotify	Searches a song and plays it.
Chrome	Opens any website.
Smart stuff happening behind the scenes
Chaining steps — Felix can do more than one thing in a row. Like "make a slideshow and then email the link to my friend." The second step can use the result of the first step.
Anti-hallucination — sometimes AI makes stuff up. We told it very firmly to ONLY use what it actually sees in the picture and to never invent fake prices or fake store names. If it can't read something, it leaves it blank instead of lying.
Intent locking* — the AI sometimes gets confused and wants to make a note for everything. So if you clearly say "email" or "spreadsheet," the backend forces it to do that thing instead of being lazy and making a note.
How it's built (the technical part)
Felix has 3 layers. Think of it like a sandwich.

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
Layer 1: The Frontend (iOS app)
This is written in Swift using SwiftUI (that's Apple's way of building app screens). Here are the important files and what they do:

File	What it does
ContentView.swift	The whole screen — camera, the status chip, the shutter button, the result popup.
CameraManager.swift	Runs the camera using AVFoundation and takes a full-quality photo when you tap capture.
SpeechRecognizer.swift	Listens with Apple's Speech framework, waits for "Hey Felix," and writes down what you say.
APIClient.swift	Takes the photo, squishes it into a JPEG, turns it into text (base64), and sends it to the backend's /ingest.
WebSocketClient.swift	Keeps a live connection open to the backend so results show up instantly. If it drops, it reconnects by itself.
Config.swift	Where you put the backend's web address.
Models.swift	The shapes of the data going in and out.
How the voice part works (this part is tricky): The mic stays on the whole time. Apple's speech recognizer turns your audio into text constantly. The code looks for the words "hey felix" inside that text, and grabs whatever you say after it as your command. When you stop talking for about 1.3 seconds, it "settles" — it keeps your words on screen and waits for you to tap capture. There's a little number called a generation counter that makes sure old, cancelled listening sessions don't mess up the new ones (this was a real bug we had to squash — without it, it only worked the first time!).

Layer 2: The Backend (the brain)
This is written in Python using FastAPI (a fast web server) and runs with uvicorn. Here's the file breakdown:

File	What it does
main.py	Starts the server and sets up the WebSocket.
routes.py	The /ingest door where the phone drops off its image + voice.
llm.py	The planner. Sends your stuff to the AI and gets back a plan.
engine.py	The worker. Runs each step of the plan in order.
tools.py	The actual real-life actions (Notes, Numbers, Gmail, etc).
websocket.py	Keeps track of everybody connected and tells them all the news.
google_svc.py	Logs into Google so it can make real Slides.
The pipeline (step by step):

The phone POSTs to /ingest with the image and voice text.
llm.py sends that to the AI and gets back a JSON plan that looks like a list of steps.
engine.py runs each step one at a time. Because controlling the Mac is slow, it runs each tool in a separate thread so the WebSocket doesn't freeze.
As each step finishes, the backend broadcasts the result to every connected phone/website over the WebSocket. That's why the result shows up live.
How it controls the Mac: the tools use a thing called AppleScript (with a command called osascript) and the open command. So when Felix "makes a note," it literally tells the Notes app "hey, make a note with this text" the same way a human would, just automatic.

Layer 3: The AI (the planner's brain)
The backend doesn't decide things by itself, it asks an AI model. It tries them in this order:

Google Gemini (if there's a GEMINI_API_KEY) — it's really good at reading images.
Groq running llama-4-scout — this is the one we use right now. It can see images too and it's super fast.
Keyword fallback — if the AI is totally down, the backend just looks for words like "email" or "spreadsheet" and guesses. Not as smart but it still works.
The AI is given a big set of instructions (called the system prompt) that tells it: only output JSON, never write a paragraph, read images word-for-word, and don't make stuff up. The JSON it sends back looks like this:

{
  "steps": [
    { "tool": "gmail.draft_email", "args": { "to": "sam@example.com", "subject": "Hi", "body": "..." } }
  ]
}
The data contracts (what the messages look like)
Phone → Backend (when you tap capture):

{
  "session_id": "ios-abc123",
  "image": "<the photo as a long base64 string>",
  "voice_text": "draft an email to my boss",
  "timestamp": 1718380800
}
Backend → Phone (live, over the WebSocket):

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
The tech stack (all the tools we used)
Swift + SwiftUI — the iPhone app
AVFoundation — the camera
Speech framework — turning your voice into text
Python + FastAPI + uvicorn — the backend server
WebSockets — live updates so results pop up instantly
Groq (llama-4-scout) / Google Gemini — the AI brains
Google Slides API — for making real presentations
AppleScript (osascript) — for controlling Mac apps
ngrok — a tunnel that gives the local backend a public web address so the phone can reach it from anywhere
How to run the whole thing
You need 3 things running at once.

1. Start the backend (the brain):

cd backend
./venv/bin/uvicorn main:app --reload --reload-dir . --reload-exclude 'venv' --port 8000
2. Start the tunnel (so the phone can reach your Mac from the internet):

ngrok http 8000
Ngrok prints a public URL like https://something.ngrok-free.dev. Copy it into ios/FelixApp/FelixApp/Config.swift (baseURL). If you have a reserved domain on your ngrok account, use ngrok http 8000 --url=your-domain.ngrok-free.dev instead.

Check it's alive by going to https://<your-ngrok-url>/health — it should say {"status":"ok"}.

3. Run the iOS app:

Open the Xcode project in ios/FelixApp/.
Make sure ios/FelixApp/FelixApp/Config.swift has the ngrok URL from step 2.
Plug in your iPhone and hit Run. (Use a real phone, not the simulator, so the camera and mic actually work.)
Setting up the AI keys
In backend/.env you put your secret keys:

GROQ_API_KEY=your_key_here
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
If you have a Gemini key, add GEMINI_API_KEY=your_key and Felix will use that instead because it reads images even better.

Why this is actually a cool idea
Most apps make you do all the work — type the email, open the spreadsheet, copy the numbers. Felix flips it around. You just show it the real world and talk like a normal human, and it turns that into real actions across a bunch of different apps. The phone, the website, whatever — they're all just different faces for the same smart backend. That's the whole point: reality goes in, finished work comes out.


---

Your task is to implement the following changes in order of priority. Do not skip steps or combine them — complete each one fully before moving to the next.

## PHASE 1: Mac Agent hardening (latency + reliability)
The current Mac agent uses AppleScript via osascript. Audit every tool in tools.py and fix:
- Any tool that takes >2s to execute: identify the bottleneck and optimize
- Any tool that can fail silently: add explicit error catching and return a structured error result
- Add retry logic (max 2 retries, 500ms backoff) for tools that interact with external apps
- Every tool must return { status: "success" | "error", message: string, data?: any }
- Write a test harness test_tools.py that runs each tool in isolation and measures execution time

## PHASE 2: Action history + undo system
Backend changes:
- Add a SQLite database (actions.db) using the schema: id, session_id, timestamp, tool_name, args_json, result_json, undo_available (bool), undo_script (text)
- Every tool execution must write a row to this table before executing
- For each tool, write a corresponding undo function. Examples: Apple Notes creation → delete the note by ID. Numbers row append → delete the last row. Gmail draft → close the tab (best effort).
- Add GET /history endpoint returning last 50 actions as JSON
- Add POST /undo/{action_id} endpoint that runs the undo_script for that action

iOS changes:
- Add a History tab to the iOS app showing the action feed from GET /history
- Each row shows: tool icon, one-line description, timestamp, and an Undo button if undo_available is true
- Tapping Undo calls POST /undo/{action_id} and shows a confirmation toast

## PHASE 3: Persistent memory
Backend changes:
- Add a memory.json file (or SQLite table) that stores user preferences learned over time
- After every successful action, extract any learnable preference and write it. Examples: "user's expense file is at ~/Documents/Expenses.numbers", "user's boss's email is boss@company.com", "user prefers Spotify over Apple Music"
- At the start of every LLM call in llm.py, inject the current memory as additional context in the system prompt
- Add GET /memory endpoint to inspect current memory
- Add DELETE /memory/{key} endpoint to let users forget specific memories

## PHASE 4: Web input client
- Create a new directory web-client/ with a self-contained HTML/JS app (no build step required, single index.html)
- It must: access the webcam and mic via browser APIs, implement the same "Hey Felix" wake word detection using the Web Speech API, show a live camera preview, send image + voice to the same /ingest endpoint as the iOS app, and display results in real time over WebSocket
- It must work when opened as a local file (file://) and when served over http
- Add a /web route to the FastAPI backend that serves this file

## PHASE 5: Multi-step autonomous tasks
Backend changes:
- Add a task queue using Python's asyncio.Queue
- Add POST /task endpoint that accepts a natural language instruction, breaks it into steps via the LLM, and queues them for background execution
- Add GET /task/{task_id}/status endpoint returning { task_id, status: "queued"|"running"|"done"|"failed", steps: [{tool, status, result}], progress_pct }
- Tasks should execute in the background without blocking the main /ingest endpoint
- Broadcast step-by-step progress over WebSocket as each step completes

iOS changes:
- Add a "Long task" mode toggle in the UI. When enabled, commands are sent to /task instead of /ingest
- The action history feed shows in-progress tasks with a live progress indicator

---

## Constraints
- Do not change the iOS app's core camera and wake word logic — it works, don't break it
- Do not change the WebSocket message format for existing events — add new event types but keep old ones intact
- Do not add any new external service dependencies for Phase 1 or 2 — SQLite and standard library only
- All new API endpoints must be documented with FastAPI's built-in OpenAPI (just use proper type annotations and docstrings)
- All new files must include a comment at the top explaining what the file does and why it exists

## How to proceed
Start with Phase 1. After completing each phase, output:
1. A summary of every file you changed and what you changed
2. How to test the new functionality manually
3. Any known limitations or deferred decisions

Then ask me to confirm before moving to the next phase.