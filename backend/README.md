# Felix Backend

Minimal FastAPI backend: receives image + voice input, runs it through Gemini
to produce structured intent JSON, and broadcasts the result to all connected
WebSocket clients.

## Setup

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then add your GEMINI_API_KEY
```

Note: `cryptography` is pinned to `42.0.8` in requirements.txt because newer
versions have no prebuilt wheel for Python 3.9 on x86_64 macOS and try to
compile from source (which needs Rust + OpenSSL). The pin avoids that.

If `GEMINI_API_KEY` is missing or the API call fails, the backend returns a
deterministic mock result so the demo always works.

## Run

```bash
uvicorn main:app --reload --port 8000
```

- Base URL: `http://localhost:8000`
- WebSocket: `ws://localhost:8000/ws`

## Endpoints

- `POST /ingest` — body `{ "session_id", "image", "voice_text" }`. Returns
  `{ action, title, content, target }`, stores it, and broadcasts over `/ws`.
- `GET /latest` — last broadcast payload.
- `GET /health` — `{ "status": "ok" }`.
- `WS /ws` — live updates. Sends the latest stored result on connect.

Broadcast payload shape:

```json
{ "session_id": "...", "event": "intent_processed", "data": { "action": "...", "title": "...", "content": "...", "target": "..." } }
```

## Example

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"session_id":"s1","image":"https://example.com/board.jpg","voice_text":"turn this into study notes"}'
```
