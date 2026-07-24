import Foundation

// Presentation-supporting network calls for the redesigned Memory & Settings
// tabs. Kept in a separate file so the core APIClient.swift stays untouched.
extension APIClient {
    /// GET /memory -> { "memory": { key: value } }
    static func memory(baseURL: String) async throws -> [String: String] {
        var req = URLRequest(url: URL(string: "\(baseURL)/memory")!)
        authorize(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            struct Detail: Codable { let detail: String? }
            let detail = (try? JSONDecoder().decode(Detail.self, from: data))?.detail
            throw NSError(domain: "Lumis", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                                     detail ?? "Server returned HTTP \(http.statusCode)."])
        }
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

    /// POST /connect/google/start — returns the Google consent URL to open in
    /// a browser. Completing it unlocks the Gmail/Sheets/Calendar tool family.
    static func googleConnectURL(baseURL: String) async throws -> URL {
        var req = URLRequest(url: URL(string: "\(baseURL)/connect/google/start")!)
        req.httpMethod = "POST"
        authorize(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        struct Resp: Codable { let url: String?; let detail: String? }
        let decoded = try? JSONDecoder().decode(Resp.self, from: data)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "Lumis", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                                     decoded?.detail ?? "Server returned HTTP \(http.statusCode)."])
        }
        guard let raw = decoded?.url, let url = URL(string: raw) else {
            throw NSError(domain: "Lumis", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No consent URL returned."])
        }
        return url
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
