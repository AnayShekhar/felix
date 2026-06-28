# Running Lumis

Lumis is three pieces: the **backend** (brain, FastAPI on Railway), the **iOS app**
(eyes/ears), and the **Mac agent** (hands). For local development you run the
backend and the Mac agent on your Mac; the iOS app talks to the backend.

## 1. Start the backend (terminal 1)

```bash
cd backend
source venv/bin/activate          # first time: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
uvicorn main:app --port 8000
```

Set `GROQ_API_KEY` in `backend/.env` (the only required key — see `.env.example`).

The backend serves, among others:
- `POST /ingest` — `{session_id, image, voice_text}` → ordered tool results
- `GET  /history` — last 50 actions
- `GET  /health` — `{"status":"ok"}`
- `WS   /ws` — live event stream
- `POST /auth/*`, `POST/GET/DELETE /link/*` — accounts + Mac pairing

## 2. Start the Mac agent (terminal 2)

```bash
LUMIS_BACKEND_URL=http://localhost:8000 ./run_mac_agent.sh
```

The agent connects over `/ws`, runs macOS-local tools (osascript / files / apps),
and prints a 6-character pairing code to link your iPhone.

## 3. Run the iOS app

Open `ios/LumisApp/LumisApp.xcodeproj` in Xcode and run on a device or simulator.
The app points at the deployed Railway backend by default (`LumisConfig`).

## Quick CLI sanity checks

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/ingest -H 'Content-Type: application/json' \
  -d '{"session_id":"test","image":"","voice_text":"what is on my calendar today"}'
curl http://localhost:8000/history
```
