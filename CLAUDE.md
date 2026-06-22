# Felix – CLAUDE.md

## Stack
- Backend: Python + FastAPI + uvicorn, SQLite for persistence, deployed on Cloud Run
- iOS: Swift + SwiftUI, iOS 17+, AVFoundation, Speech framework, no third-party deps
- Mac: SwiftUI menu bar app, LSUIElement = YES
- AI: Gemini (primary, multimodal), Groq llama-4-scout (fallback)
- Realtime: WebSocket for live event broadcasting

## Repo layout
backend/        FastAPI server — all AI logic lives here
ios/            SwiftUI iOS app — input layer only
macos-app/      SwiftUI menu bar app — dashboard + tray
web-client/     Single-file HTML/JS fallback frontend

## Hard constraints
- NEVER touch CameraManager.swift or SpeechRecognizer.swift
- NEVER add Python dependencies without asking first
- NEVER put AI logic in any frontend — backend only
- All API errors must surface in UI, no silent console-only failures
- Dark mode only across all frontends
- SF Pro font, single brand accent color (not blue, not purple)

## API contracts
POST /ingest        { session_id, image (base64), voice_text, timestamp }
GET  /history       returns last 50 actions
GET  /memory        returns learned user preferences as key/value
DELETE /memory/:key removes one memory entry
GET  /health        returns { status: "ok", latency_ms }
WS   /ws            real-time event stream

## Key patterns
- Backend broadcasts all events over WebSocket — frontends never poll
- All tools return { status: "success"|"error", message: string, data?: any }
- Backend URL stored in UserDefaults key: felix.backendURL, defaults to http://localhost:8000
- Session IDs prefixed by client type: "ios-", "web-", "mac-"