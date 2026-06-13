# Running the Felix Demo

End-to-end flow: the web dashboard's **Send Test Input** button POSTs to the backend,
the backend runs Gemini (or a deterministic mock fallback), stores the latest result,
and broadcasts it over a WebSocket. The dashboard updates instantly.

## 1. Start the backend (terminal 1)

```bash
cd backend
source venv/bin/activate          # first time: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
uvicorn main:app --port 8000
```

The backend serves:
- `POST /ingest` — accepts `{session_id, image, voice_text}`, returns `{action, title, content, target}`
- `GET  /latest` — last broadcast event
- `GET  /health` — `{"status":"ok"}`
- `WS   /ws`     — broadcasts `{session_id, event:"intent_processed", data:{action,title,content,target}}`

### Real Gemini vs. mock fallback

By default the backend has **no API key**, so it returns a deterministic **mock**
result — the full demo pipeline still works end to end without any key.

To use real Gemini, add a key to `backend/.env`:

```bash
cd backend
echo "GEMINI_API_KEY=your_real_key_here" > .env   # see .env.example
```

Then restart uvicorn. If the key is missing or the Gemini call fails, the backend
automatically falls back to the mock result (the demo never crashes).

## 2. Start the frontend (terminal 2)

```bash
cd web
npm install      # first time only
npm run dev      # serves on http://localhost:3000
```

The frontend reads its endpoints from `web/lib/config.ts` (overridable via
`NEXT_PUBLIC_API_BASE_URL` / `NEXT_PUBLIC_WS_URL`). Defaults:
- Ingest: `http://localhost:8000/ingest`
- WebSocket: `ws://localhost:8000/ws`

## 3. Run the demo

1. Open <http://localhost:3000> in a browser.
2. The "Live Output" panel should show **connected** (WebSocket connected to the backend).
3. Click **Send Test Input**. It POSTs:
   ```json
   {"session_id":"test","image":"mock.jpg","voice_text":"turn this into study notes"}
   ```
4. The Live Output panel updates instantly with the AI interpretation
   (title, action, target, content) and the formatted JSON.

> A client that connects *after* an ingest immediately receives the last stored
> result, so the panel populates on page load too.

## Quick CLI sanity checks

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/ingest -H 'Content-Type: application/json' \
  -d '{"session_id":"test","image":"mock.jpg","voice_text":"turn this into study notes"}'
curl http://localhost:8000/latest
```
