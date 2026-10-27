import Foundation

/// The authenticated user, as returned by the backend `/auth/*` endpoints.
struct FelixUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    var name: String?
    var provider: String?

    /// Up-to-two-letter initials for the Settings avatar.
    var initials: String {
        let source = (name?.isEmpty == false ? name! : email)
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        let letters = parts.prefix(2).compactMap { $0.first }
        let joined = String(letters).uppercased()
        return joined.isEmpty ? "?" : joined
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return email.split(separator: "@").first.map(String.init) ?? email
    }
}

/// `{ token, user }` envelope returned by register/login/apple/google.
struct AuthResponse: Codable {
    let token: String
    let user: FelixUser
}

/// `{ user }` envelope returned by `GET /auth/me`.
struct MeResponse: Codable {
    let user: FelixUser
}
