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

    // MARK: - Auth token (shared with AuthStore via UserDefaults)

    static var token: String? {
        get { UserDefaults.standard.string(forKey: LumisBrand.authTokenKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: LumisBrand.authTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: LumisBrand.authTokenKey)
            }
        }
    }

    /// A GET/DELETE request carrying the bearer token (per-account scoping).
    private static func authed(_ path: String, method: String = "GET") throws -> URLRequest {
        var req = URLRequest(url: try url(path))
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
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
            let (data, resp) = try await URLSession.shared.data(for: try authed("/history"))
            try check(resp)
            return (try? JSONDecoder().decode(HistoryResponse.self, from: data))?.actions ?? []
        } catch { throw friendly(error) }
    }

    // MARK: - Memory

    static func memory() async throws -> [String: String] {
        do {
            let (data, resp) = try await URLSession.shared.data(for: try authed("/memory"))
            try check(resp)
            return (try? JSONDecoder().decode(MemoryResponse.self, from: data))?.memory ?? [:]
        } catch { throw friendly(error) }
    }

    static func forget(key: String) async throws {
        do {
            let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            let (_, resp) = try await URLSession.shared.data(for: try authed("/memory/\(encoded)", method: "DELETE"))
            try check(resp)
        } catch { throw friendly(error) }
    }

    // MARK: - Auth

    static func login(email: String, password: String) async throws -> AuthUser {
        try await authPost("/auth/login", body: ["email": email, "password": password])
    }

    static func register(name: String, email: String, password: String) async throws -> AuthUser {
        try await authPost("/auth/register", body: ["name": name, "email": email, "password": password])
    }

    /// Sign in with Apple — same endpoint + JWT as iOS.
    static func apple(identityToken: String, fullName: String) async throws -> AuthUser {
        try await authPost("/auth/apple", body: ["identityToken": identityToken, "fullName": fullName])
    }

    /// Sign in with Google — same endpoint + JWT as iOS.
    static func google(idToken: String) async throws -> AuthUser {
        try await authPost("/auth/google", body: ["idToken": idToken])
    }

    /// GET /auth/me — validates the stored token and returns the account.
    static func me() async throws -> AuthUser {
        do {
            let (data, resp) = try await URLSession.shared.data(for: try authed("/auth/me"))
            try check(resp)
            return try JSONDecoder().decode(MeEnvelope.self, from: data).user
        } catch { throw friendly(error) }
    }

    /// POST an auth credential, store the returned token, return the user.
    private static func authPost(_ path: String, body: [String: String]) async throws -> AuthUser {
        do {
            var req = URLRequest(url: try url(path))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.detail
                throw APIError(message: detail ?? "Sign-in failed (HTTP \(http.statusCode)).")
            }
            let envelope = try JSONDecoder().decode(AuthEnvelope.self, from: data)
            token = envelope.token
            return envelope.user
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

    // MARK: - Linking (account-bound, 6-digit code)

    /// The signed-in Mac asks the backend for a fresh 6-digit pairing code.
    static func generateLinkCode(macId: String, macName: String) async throws -> LinkCodeResponse {
        do {
            var req = try authed("/link/generate", method: "POST")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["mac_id": macId, "mac_name": macName])
            let (data, resp) = try await URLSession.shared.data(for: req)
            try check(resp)
            return try JSONDecoder().decode(LinkCodeResponse.self, from: data)
        } catch { throw friendly(error) }
    }

    /// The pairing state for the signed-in account (works for phone + Mac).
    static func linkStatus() async throws -> LinkStatusResponse {
        do {
            let (data, resp) = try await URLSession.shared.data(for: try authed("/link/status"))
            try check(resp)
            return try JSONDecoder().decode(LinkStatusResponse.self, from: data)
        } catch { throw friendly(error) }
    }

    /// Keep this Mac marked "online" for the paired phone.
    static func heartbeat(macId: String, macName: String) async throws {
        do {
            var request = URLRequest(url: try url("/link/heartbeat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["mac_id": macId, "mac_name": macName])
            _ = try await URLSession.shared.data(for: request)
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
