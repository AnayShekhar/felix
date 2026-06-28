import Foundation

/// Thrown when an API call fails, carrying a human message suitable for inline
/// display (never a silent console-only failure).
struct APIError: LocalizedError, Identifiable {
    let id = UUID()
    let message: String
    var errorDescription: String? { message }
}

/// All backend HTTP calls for the macOS app. async/await, surfaces failures.
enum APIService {
    private static func base() -> String {
        let stored = UserDefaults.standard.string(forKey: LumisBrand.backendURLKey)
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? LumisBrand.defaultBackendURL : trimmed
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private static func url(_ path: String) throws -> URL {
        guard let u = URL(string: base() + path) else {
            throw APIError(message: "Invalid backend URL. Check Settings.")
        }
        return u
    }

    private static func friendly(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return APIError(message: "Can't reach the backend. Is it running?")
            case NSURLErrorTimedOut:
                return APIError(message: "The backend timed out.")
            case NSURLErrorNotConnectedToInternet:
                return APIError(message: "No network connection.")
            default:
                return APIError(message: ns.localizedDescription)
            }
        }
        return APIError(message: error.localizedDescription)
    }

    // MARK: - History

    static func history() async throws -> [ActionHistoryItem] {
        do {
            let (data, resp) = try await URLSession.shared.data(from: try url("/history"))
            try check(resp)
            return (try? JSONDecoder().decode(HistoryResponse.self, from: data))?.actions ?? []
        } catch { throw friendly(error) }
    }

    // MARK: - Memory

    static func memory() async throws -> [String: String] {
        do {
            let (data, resp) = try await URLSession.shared.data(from: try url("/memory"))
            try check(resp)
            return (try? JSONDecoder().decode(MemoryResponse.self, from: data))?.memory ?? [:]
        } catch { throw friendly(error) }
    }

    static func forget(key: String) async throws {
        do {
            let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            var req = URLRequest(url: try url("/memory/\(encoded)"))
            req.httpMethod = "DELETE"
            let (_, resp) = try await URLSession.shared.data(for: req)
            try check(resp)
        } catch { throw friendly(error) }
    }

    // MARK: - Undo

    @discardableResult
    static func undo(actionID: Int) async throws -> UndoResponse {
        do {
            var req = URLRequest(url: try url("/undo/\(actionID)"))
            req.httpMethod = "POST"
            let (data, resp) = try await URLSession.shared.data(for: req)
            try check(resp)
            return try JSONDecoder().decode(UndoResponse.self, from: data)
        } catch { throw friendly(error) }
    }

    // MARK: - Mac agent

    /// Whether the Mac agent (mac_agent.py) is currently connected to the backend.
    static func macConnected() async throws -> Bool {
        do {
            let (data, resp) = try await URLSession.shared.data(from: try url("/mac/status"))
            try check(resp)
            return (try? JSONDecoder().decode(MacStatusResponse.self, from: data))?.connected ?? false
        } catch { throw friendly(error) }
    }

    // MARK: - Health

    /// Returns measured round-trip latency in milliseconds.
    static func health() async throws -> Int {
        do {
            let start = Date()
            let (_, resp) = try await URLSession.shared.data(from: try url("/health"))
            try check(resp)
            return Int(Date().timeIntervalSince(start) * 1000)
        } catch { throw friendly(error) }
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw APIError(message: "Backend returned HTTP \(http.statusCode).")
        }
    }
}
