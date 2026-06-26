import Foundation

// Matches the backend input contract: { session_id, image, voice_text, timestamp }
struct IngestPayload: Codable {
    let session_id: String
    let image: String        // base64-encoded JPEG (or "" if none)
    let voice_text: String
    let timestamp: Double
}

// A single tool-execution result from the backend.
// Backend step result: { tool, status, message, title, detail, url?, speak?, summary? }
struct StepResult: Codable, Identifiable {
    var id: String { (tool ?? "") + (title ?? "") + (message ?? "") }
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
    let speak: String?       // short spoken summary (Fix 7); empty for action-only tools
    let summary: String?     // longer formatted display text (Fix 8); content tools only
}

// /ingest response: { "steps": [StepResult] }
struct IngestResponse: Codable {
    let steps: [StepResult]?
}

// One row from GET /history. Matches backend db._row_to_dict output.
struct ActionHistoryItem: Codable, Identifiable {
    let id: Int
    let session_id: String?
    let timestamp: Double?
    let tool_name: String?
    let status: String?
    let message: String?
    let title: String?
    let undo_available: Bool
}

// GET /history response: { "actions": [ActionHistoryItem] }
struct HistoryResponse: Codable {
    let actions: [ActionHistoryItem]?
}

// POST /undo/{id} response: { action_id, status, message }
struct UndoResponse: Codable {
    let action_id: Int?
    let status: String?
    let message: String?
}

// WebSocket envelope: { session_id, event, data }
// Events: "step_started", "step_executed", "workflow_complete", "action_undone"
struct WSEnvelope: Codable {
    let session_id: String?
    let event: String?
    let data: WSData?
}

// Flexible payload covering per-step, workflow_complete, and task_* events.
struct WSData: Codable {
    let index: Int?
    let total: Int?
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
    let speak: String?         // short spoken summary (Fix 7)
    let summary: String?       // longer formatted display text (Fix 8)
    let steps: [StepResult]?   // present on workflow_complete
    let task_id: String?       // present on task_started/task_progress/task_complete
    let progress_pct: Int?     // present on task_progress/task_complete
    let instruction: String?   // present on task_started
}

// POST /task response: { task_id, status }
struct TaskCreateResponse: Codable {
    let task_id: String?
    let status: String?
}

// Live state of a background autonomous task (Phase 5), driven by WS events.
struct TaskState: Identifiable {
    let id: String          // task_id
    var instruction: String
    var status: String      // queued | running | done | failed
    var progressPct: Int
    var active: Bool { status == "queued" || status == "running" }
}
