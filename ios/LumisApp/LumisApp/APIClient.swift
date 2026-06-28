import Foundation
import UIKit

enum APIClient {
    /// Attaches the signed-in account's bearer token so the backend can scope
    /// per-account history + memory. No-op if not signed in.
    static func authorize(_ req: inout URLRequest) {
        if let token = KeychainManager.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    /// POSTs an image + voice command to the backend's /ingest endpoint.
    @discardableResult
    static func ingest(
        image: UIImage?,
        voiceText: String,
        sessionID: String,
        baseURL: String
    ) async throws -> [StepResult] {
        let base64 = image?
            .jpegData(compressionQuality: 0.85)?
            .base64EncodedString() ?? ""

        let payload = IngestPayload(
            session_id: sessionID,
            image: base64,
            voice_text: voiceText,
            timestamp: Date().timeIntervalSince1970
        )

        var req = URLRequest(url: Config.ingestURL(base: baseURL))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode(IngestResponse.self, from: data))?.steps ?? []
    }

    /// Fetches the last 50 actions for the signed-in account (GET /history).
    static func history(baseURL: String) async throws -> [ActionHistoryItem] {
        var req = URLRequest(url: Config.historyURL(base: baseURL))
        authorize(&req)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode(HistoryResponse.self, from: data))?.actions ?? []
    }

    /// Queues a long-running autonomous task via POST /task (Phase 5).
    @discardableResult
    static func createTask(
        instruction: String,
        sessionID: String,
        baseURL: String
    ) async throws -> TaskCreateResponse {
        var req = URLRequest(url: Config.taskURL(base: baseURL))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["instruction": instruction, "session_id": sessionID]
        )
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(TaskCreateResponse.self, from: data)
    }

    /// Requests an undo of a single action via POST /undo/{id}.
    static func undo(actionID: Int, baseURL: String) async throws -> UndoResponse {
        var req = URLRequest(url: Config.undoURL(base: baseURL, actionID: actionID))
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(UndoResponse.self, from: data)
    }
}
