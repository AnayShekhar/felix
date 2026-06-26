import Foundation

/// Groq Whisper transcription client (Hotfix 1).
///
/// Apple's Speech framework mishears proper nouns badly ("Anay Shekhar" ->
/// "a shaker"), which breaks any command with a name. We keep Apple Speech only
/// for the two-word "Hey Felix" wake phrase and route the actual command audio
/// to Groq's `whisper-large-v3-turbo` endpoint, which is far more accurate on
/// names and technical terms. Callers fall back to the Apple transcript silently
/// when this throws (no key, offline, API error).
enum WhisperTranscriber {
    /// UserDefaults key holding the user's Groq API key (entered in Settings).
    static let apiKeyDefaultsKey = "felix.groqAPIKey"

    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private static let model = "whisper-large-v3-turbo"

    enum TranscribeError: Error { case missingKey, badResponse, empty }

    /// The configured Groq key, or nil if the user hasn't entered one.
    static var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    static var isConfigured: Bool { apiKey != nil }

    /// Transcribe an audio file (wav/m4a) via Groq Whisper. Throws on any failure
    /// so the caller can fall back to Apple Speech.
    static func transcribe(fileURL: URL) async throws -> String {
        guard let key = apiKey else { throw TranscribeError.missingKey }

        let boundary = "felix-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let audio = try Data(contentsOf: fileURL)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("language", "en")
        field("response_format", "json")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscribeError.badResponse
        }
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw TranscribeError.empty }
        return text
    }

    private struct WhisperResponse: Decodable { let text: String }
}
