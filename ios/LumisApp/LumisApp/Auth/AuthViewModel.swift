import AuthenticationServices
import Combine
import Foundation
import SwiftUI

/// Owns all authentication state. No screen is reachable unless
/// `isAuthenticated` is true. Token + cached user live in the Keychain.
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: LumisUser?
    @Published var isLoading = true          // true on launch → Splash
    @Published var error: String?

    private var token: String? { KeychainManager.token }

    // MARK: - Launch

    /// Validate any stored token against `GET /auth/me`. 401 → sign out.
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        guard let token else { return }
        // Optimistically show cached user while we validate.
        currentUser = KeychainManager.loadUser()
        do {
            let me = try await LumisAPI.request("/auth/me", token: token, as: MeResponse.self)
            currentUser = me.user
            KeychainManager.saveUser(me.user)
            isAuthenticated = true
        } catch let e as LumisAPIError where e.isUnauthorized {
            signOutLocal()
        } catch {
            // Network blip: keep the cached session so the app still opens.
            if currentUser != nil { isAuthenticated = true }
        }
    }

    // MARK: - Email / password

    func login(email: String, password: String) async {
        await run {
            let body = ["email": email, "password": password]
            let resp = try await LumisAPI.request("/auth/login", method: "POST", body: body, as: AuthResponse.self)
            self.apply(resp)
        }
    }

    func register(name: String, email: String, password: String) async {
        await run {
            let body = ["name": name, "email": email, "password": password]
            let resp = try await LumisAPI.request("/auth/register", method: "POST", body: body, as: AuthResponse.self)
            self.apply(resp)
        }
    }

    /// No backend reset endpoint exists yet; this confirms the flow client-side.
    func sendPasswordReset(email: String) async -> Bool {
        guard email.contains("@") else {
            error = "Enter a valid email address."
            return false
        }
        return true
    }

    // MARK: - Sign in with Apple

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = err.localizedDescription
        case .success(let auth):
            guard
                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                error = "Apple sign-in failed."
                return
            }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task {
                await run {
                    let body = ["identityToken": identityToken, "fullName": fullName]
                    let resp = try await LumisAPI.request("/auth/apple", method: "POST", body: body, as: AuthResponse.self)
                    self.apply(resp)
                }
            }
        }
    }

    // MARK: - Sign in with Google

    private let google = GoogleAuthSession()

    func signInWithGoogle() async {
        await run {
            let idToken = try await self.google.obtainIDToken()
            let resp = try await LumisAPI.request("/auth/google", method: "POST", body: ["idToken": idToken], as: AuthResponse.self)
            self.apply(resp)
        }
    }

    // MARK: - Session lifecycle

    func logout() {
        if let token { Task { _ = try? await LumisAPI.requestVoid("/auth/logout", token: token) } }
        signOutLocal()
    }

    func deleteAccount() async {
        guard let token else { return }
        await run {
            _ = try await LumisAPI.requestVoid("/auth/account", method: "DELETE", token: token)
            self.signOutLocal()
        }
    }

    func changeEmail(newEmail: String, password: String) async -> Bool {
        guard let token else { return false }
        var ok = false
        await run {
            let resp = try await LumisAPI.request(
                "/auth/change-email", method: "POST",
                body: ["newEmail": newEmail, "password": password], token: token, as: AuthResponse.self)
            self.apply(resp)
            ok = true
        }
        return ok
    }

    func changePassword(current: String, newPassword: String) async -> Bool {
        guard let token else { return false }
        var ok = false
        await run {
            _ = try await LumisAPI.requestVoid(
                "/auth/change-password", method: "POST",
                body: ["currentPassword": current, "newPassword": newPassword], token: token)
            ok = true
        }
        return ok
    }

    func refreshUser() async {
        guard let token else { return }
        if let me = try? await LumisAPI.request("/auth/me", token: token, as: MeResponse.self) {
            currentUser = me.user
            KeychainManager.saveUser(me.user)
        }
    }

    // MARK: - Helpers

    private func apply(_ resp: AuthResponse) {
        KeychainManager.token = resp.token
        KeychainManager.saveUser(resp.user)
        currentUser = resp.user
        isAuthenticated = true
        error = nil
    }

    private func signOutLocal() {
        KeychainManager.clear()
        currentUser = nil
        isAuthenticated = false
    }

    /// Runs an async auth action with shared loading/error handling.
    private func run(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await action()
        } catch let e as LumisAPIError {
            error = e.errorDescription
        } catch let e as GoogleAuthSession.GoogleAuthError {
            if case .cancelled = e { return }
            error = e.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
