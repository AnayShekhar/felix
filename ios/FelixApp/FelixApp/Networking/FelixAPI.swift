import Foundation

/// Surfaced API errors. Every failure carries a human message so the UI can
/// show it (no silent console-only failures).
enum FelixAPIError: LocalizedError {
    case unauthorized
    case server(Int, String)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .unauthorized:         return "Your session expired. Sign in again."
        case .server(_, let msg):   return msg
        case .network(let msg):     return msg
        case .decoding:             return "Unexpected response from the server."
        }
    }

    var isUnauthorized: Bool { if case .unauthorized = self { return true }; return false }
}

/// Minimal typed JSON client for the Felix backend.
enum FelixAPI {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        token: String? = nil,
        as type: T.Type
    ) async throws -> T {
        let data = try await raw(path, method: method, body: body, token: token)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FelixAPIError.decoding
        }
    }

    @discardableResult
    static func requestVoid(
        _ path: String,
        method: String = "POST",
        body: Encodable? = nil,
        token: String? = nil
    ) async throws -> Data {
        try await raw(path, method: method, body: body, token: token)
    }

    // MARK: - Core

    private static func raw(
        _ path: String,
        method: String,
        body: Encodable?,
        token: String?
    ) async throws -> Data {
        guard let url = URL(string: FelixConfig.backendURL + path) else {
            throw FelixAPIError.network("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try? encoder.encode(AnyEncodable(body)) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FelixAPIError.network("Couldn't reach the server. Check your connection.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw FelixAPIError.network("No response from server.")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw FelixAPIError.unauthorized
        default:
            throw FelixAPIError.server(http.statusCode, Self.detail(from: data, status: http.statusCode))
        }
    }

    /// Pull FastAPI's `{ "detail": "..." }` message out of an error body.
    private static func detail(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["detail"] as? String { return s }
            if let arr = obj["detail"] as? [[String: Any]],
               let msg = arr.first?["msg"] as? String { return msg }
        }
        return "Request failed (\(status))."
    }
}

/// Type-erasing wrapper so we can encode a heterogeneous `Encodable` body.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
