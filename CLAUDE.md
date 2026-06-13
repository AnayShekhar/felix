# CLAUDE.md – Felix PRD

## Project Name
Felix

## One-Line Description
Felix is a frontend-agnostic system where any device (iOS, web, or desktop) can capture real-world context (image + voice), send it to a Google Cloud backend powered by Gemini, and receive structured actions that can be displayed or executed anywhere in real time.

## Core Idea
The backend is the product. Frontends are interchangeable. Any client can send input and receive structured workflow output.

---

## System Design

Felix is split into three layers:

### 1. Frontend Clients (replaceable)

**Implementations:**
- iOS Swift app (primary for hackathon)
- Web app (dashboard / fallback frontend)
- Future desktop or other clients

**Responsibilities:**
- Capture image or camera input
- Capture voice command
- Send standardized payload to backend via HTTP
- Listen for real-time updates via WebSocket
- Render results — no AI logic in frontend

---

### 2. Backend (Google Cloud Run)

This is the intelligence layer for Felix.

**Responsibilities:**
- Receive input from any frontend
- Send image + voice to Gemini
- Convert input into structured intent JSON
- Broadcast result to all connected clients via WebSocket
- Manage sessions

**Core rule:** Backend handles ALL AI and logic. Frontends do NOT interpret data.

---

### 3. Gemini (AI Brain)

Used only in backend.

**Purpose:** Convert image + voice into structured workflow commands.

**Example input:** image + `"turn this into study notes"`

**Example output:**
```json
{
  "action": "create_notes",
  "title": "Photosynthesis",
  "content": "...",
  "target": "dashboard"
}
```

---

## Data Contracts

### Input Payload (frontend → backend)
```json
{
  "session_id": "string",
  "image": "string (base64 or URL)",
  "voice_text": "string",
  "timestamp": "number"
}
```

### Output Payload (backend → frontend)
```json
{
  "session_id": "string",
  "action": "string",
  "title": "string",
  "content": "string",
  "target": "string"
}
```

### Event Stream (WebSocket)
```json
{
  "session_id": "string",
  "event": "intent_processed",
  "data": "<output_payload>"
}
```

---

## Frontend Requirements

All Felix frontends must:
- Capture input (image + voice or equivalent)
- Send POST request to `/ingest`
- Subscribe to WebSocket session channel
- Render backend output

### iOS Swift App (Hackathon Primary)
- Camera capture via `AVFoundation`
- Voice capture via `Speech` framework
- API client for backend communication
- WebSocket client for live updates
- Minimal UI: capture screen + session screen

### Web Dashboard
- Live session viewer
- Shows incoming images, voice transcript, AI output
- History view of past sessions
- Replay view (input → output timeline)

---

## Backend Structure

```
backend/
├── main.py
├── routes/
│   ├── ingest.py
│   ├── sessions.py
│   └── websocket.py
├── core/
│   ├── gemini_engine.py
│   ├── intent_parser.py
│   └── event_bus.py
└── services/
    ├── session_manager.py
    └── storage.py
```

### Key Backend Flow

1. Receive payload from frontend
2. Store session data
3. Send image + voice to Gemini
4. Parse Gemini response into structured JSON
5. Broadcast result via WebSocket to all clients

---

## Google Cloud Usage

| Service | Role |
|---|---|
| Cloud Run | Hosts backend API |
| Gemini API | Multimodal reasoning (image + voice → intent) |
| WebSocket server | Runs on backend instance |
| Storage (optional) | Session history persistence |

---

## Why This System Is a New Interface

Instead of users typing or clicking, they capture real-world context and speak intent. Felix converts real-world input into structured digital workflows that execute across apps.

---

## MVP Scope (Hackathon — 5 Hours)

### Must Have
- Swift app (camera + voice + send)
- Backend with Gemini integration
- Web dashboard showing live results

### Optional
- Desktop execution layer (not required for demo)

---

## Demo Flow

1. Open iOS app
2. Point at whiteboard or notes
3. Say a command: `"turn this into notes"`
4. Backend processes via Gemini
5. Web dashboard updates instantly with generated output

---

## End Goal

Felix is a system where reality becomes structured digital workflows through a universal AI backend, independent of any specific frontend.
