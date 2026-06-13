import Foundation

// Matches the backend input contract: { session_id, image, voice_text, timestamp }
struct IngestPayload: Codable {
    let session_id: String
    let image: String        // base64-encoded JPEG (or "" if none)
    let voice_text: String
    let timestamp: Double
}

// A single tool-execution result from the backend.
// Backend step result: { tool, status, message, title, detail, url? }
struct StepResult: Codable, Identifiable {
    var id: String { (tool ?? "") + (title ?? "") + (message ?? "") }
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
}

// /ingest response: { "steps": [StepResult] }
struct IngestResponse: Codable {
    let steps: [StepResult]?
}

// WebSocket envelope: { session_id, event, data }
// Events: "step_started", "step_executed", "workflow_complete"
struct WSEnvelope: Codable {
    let session_id: String?
    let event: String?
    let data: WSData?
}

// Flexible payload covering both per-step events and workflow_complete.
struct WSData: Codable {
    let index: Int?
    let total: Int?
    let tool: String?
    let status: String?
    let message: String?
    let title: String?
    let detail: String?
    let url: String?
    let steps: [StepResult]?   // present on workflow_complete
}
