import Foundation

// Matches the backend input contract: { session_id, image, voice_text, timestamp }
struct IngestPayload: Codable {
    let session_id: String
    let image: String        // base64-encoded JPEG (or "" if none)
    let voice_text: String
    let timestamp: Double
}

// Matches the backend output contract: { action, title, content, target }
struct IntentResult: Codable, Identifiable {
    var id: String { title + action }
    let action: String
    let title: String
    let content: String
    let target: String
}

// WebSocket envelope: { session_id, event, data: IntentResult }
struct WSEvent: Codable {
    let session_id: String
    let event: String
    let data: IntentResult
}
