# Running Lumis

Lumis is three pieces: the **backend** (brain, FastAPI on Railway), the **iOS app**
(eyes/ears), and the **Chrome extension** (connects your accounts). Execution is
100% cloud — the backend runs every tool via Google REST APIs, a Browserbase cloud
browser, or a phone-side URL scheme. There is no Mac app or Mac agent to run.

## 1. Start the backend (terminal 1)

```bash
cd backend
source venv/bin/activate          # first time: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
uvicorn main:app --port 8000
```

Set these in `backend/.env` (see `.env.example`):
- `GROQ_API_KEY` — the only required AI key (Groq)
- `GROQ_MODEL` — optional; defaults to `qwen/qwen3.6-27b` (multimodal)
- `BROWSERBASE_API_KEY`, `BROWSERBASE_PROJECT_ID` — cloud browser
- `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` — Google API tools

The backend serves, among others:
- `POST /ingest` — `{session_id, image, voice_text}` → runs the ReAct agent
- `GET  /history` — last 50 actions
- `GET  /health` — `{"status":"ok"}`
- `WS   /ws` — live event stream (broadcast-only to clients)
- `POST /auth/*` — accounts
- `GET  /connect/status`, `POST /connect/cookies/sync` — connected services

## 2. Run the iOS app

Open `ios/LumisApp/LumisApp.xcodeproj` in Xcode and run on a device or simulator.
The app points at the deployed Railway backend by default (`LumisConfig`).

## 3. Connect your accounts (Chrome extension)

Load the unpacked `chrome-extension/` in Chrome (`chrome://extensions` → Developer
mode → Load unpacked). Sign in with the same Lumis account used on your phone, then
connect each service — its logged-in cookies sync to your private Browserbase
context so the cloud browser is already signed in. Google API tools additionally
require the Google OAuth consent flow.

## Quick CLI sanity checks

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/ingest -H 'Content-Type: application/json' \
  -d '{"session_id":"test","image":"","voice_text":"what is on my calendar today"}'
curl http://localhost:8000/history
```
