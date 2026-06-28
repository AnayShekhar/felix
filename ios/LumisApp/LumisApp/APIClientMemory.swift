import Foundation

// Presentation-supporting network calls for the redesigned Memory & Settings
// tabs. Kept in a separate file so the core APIClient.swift stays untouched.
extension APIClient {
    /// GET /memory -> { "memory": { key: value } }
    static func memory(baseURL: String) async throws -> [String: String] {
        var req = URLRequest(url: URL(string: "\(baseURL)/memory")!)
        authorize(&req)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Resp: Codable { let memory: [String: String]? }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.memory ?? [:]
    }

    /// DELETE /memory/{key}
    static func forget(key: String, baseURL: String) async throws {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        var req = URLRequest(url: URL(string: "\(baseURL)/memory/\(encoded)")!)
        req.httpMethod = "DELETE"
        authorize(&req)
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "Lumis", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
    }

    /// GET /health — returns measured round-trip latency in milliseconds.
    static func health(baseURL: String) async throws -> Int {
        let start = Date()
        let (_, resp) = try await URLSession.shared.data(from: URL(string: "\(baseURL)/health")!)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "Lumis", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return Int(Date().timeIntervalSince(start) * 1000)
    }
}
