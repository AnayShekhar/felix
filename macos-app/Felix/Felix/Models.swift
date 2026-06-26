import Foundation

// Mirrors the backend API contract (see CLAUDE.md). The macOS app is a
// read/observe client: it reads /history and /memory, deletes memory keys,
// undoes actions, checks /health, and streams /ws.

/// One tool-execution result (a step inside a workflow).
struct StepResult: Codable, Identifiable {
    var id: String { (tool ?? "") + (title ?? "") + (message ?? "") }
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
}

/// One row from GET /history.
struct ActionHistoryItem: Codable, Identifiable {
    let id: Int
    let session_id: String?
    let timestamp: Double?
    let tool_name: String?
    let status: String?
    let message: String?
    let title: String?
    let summary: String?     // formatted display text for content tools (Fix 8)
    let undo_available: Bool
}

struct HistoryResponse: Codable {
    let actions: [ActionHistoryItem]?
}

/// GET /memory -> { "memory": { key: value } }
struct MemoryResponse: Codable {
    let memory: [String: String]?
}

/// POST /undo/{id} -> { action_id, status, message }
struct UndoResponse: Codable {
    let action_id: Int?
    let status: String?
    let message: String?
}

/// GET /mac/status -> { connected, agents }
struct MacStatusResponse: Codable {
    let connected: Bool?
    let agents: Int?
}

/// WebSocket envelope: { session_id, event, data }
struct WSEnvelope: Codable {
    let session_id: String?
    let event: String?
    let data: WSData?
}

struct WSData: Codable {
    let index: Int?
    let total: Int?
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
    let steps: [StepResult]?
    let task_id: String?
    let progress_pct: Int?
    let instruction: String?
}

/// A single rendered card in the live event feed (right panel).
struct FeedEvent: Identifiable {
    let id = UUID()
    let event: String        // "step_executed", "workflow_complete", ...
    let tool: String?
    let status: String?      // "success" | "error" | nil
    let message: String
    let receivedAt: Date

    var isError: Bool { (status ?? "").lowercased() == "error" }
}
