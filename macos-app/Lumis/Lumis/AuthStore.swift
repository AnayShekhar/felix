import SwiftUI

/// Account state for the macOS app. Signs into the SAME Lumis account as the
/// iPhone (same /auth endpoints), so history + memory are shared per-account.
/// The bearer token lives in UserDefaults under `LumisBrand.authTokenKey` and is
/// read by `APIService` to authorize every request.
@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var displayName = ""
    @Published var email = ""
    @Published var error: String?
    @Published var busy = false
    @Published var booting = true

    var initials: String {
        let source = displayName.isEmpty ? email : displayName
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }

    /// Validate any stored token on launch.
    func bootstrap() async {
        booting = true
        defer { booting = false }
        guard APIService.token != nil else { return }
        do {
            let user = try await APIService.me()
            apply(user)
        } catch {
            // Keep the user signed out if the token is invalid; surface nothing.
            signOut()
        }
    }

    func login(email: String, password: String) async {
        await run { try await APIService.login(email: email, password: password) }
    }

    func register(name: String, email: String, password: String) async {
        await run { try await APIService.register(name: name, email: email, password: password) }
    }

    func loginApple(identityToken: String, fullName: String) async {
        await run { try await APIService.apple(identityToken: identityToken, fullName: fullName) }
    }

    private let google = GoogleAuthSessionMac()

    func loginGoogle() async {
        await run {
            let idToken = try await self.google.obtainIDToken()
            return try await APIService.google(idToken: idToken)
        }
    }

    func signOut() {
        APIService.token = nil
        isAuthenticated = false
        displayName = ""
        email = ""
    }

    // MARK: - Helpers

    private func apply(_ user: AuthUser) {
        displayName = user.name ?? ""
        email = user.email
        isAuthenticated = true
        error = nil
    }

    private func run(_ action: @escaping () async throws -> AuthUser) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            apply(try await action())
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
