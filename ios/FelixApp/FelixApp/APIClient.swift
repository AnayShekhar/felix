import Foundation
import UIKit

enum APIClient {
    /// POSTs an image + voice command to the backend's /ingest endpoint.
    /// The structured results also arrive over the WebSocket, so the UI renders
    /// live updates from there; the returned steps are best-effort.
    @discardableResult
    static func ingest(image: UIImage?, voiceText: String, sessionID: String) async throws -> [StepResult] {
        // Higher quality => more reliable text extraction (OCR) by the model.
        let base64 = image?
            .jpegData(compressionQuality: 0.85)?
            .base64EncodedString() ?? ""

        let payload = IngestPayload(
            session_id: sessionID,
            image: base64,
            voice_text: voiceText,
            timestamp: Date().timeIntervalSince1970
        )

        var req = URLRequest(url: Config.ingestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        // Tolerate shape differences — UI is driven by the WebSocket.
        return (try? JSONDecoder().decode(IngestResponse.self, from: data))?.steps ?? []
    }
}
