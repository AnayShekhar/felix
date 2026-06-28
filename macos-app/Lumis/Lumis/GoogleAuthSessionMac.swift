import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Dependency-free "Sign in with Google" for macOS using
/// ASWebAuthenticationSession + OAuth 2.0 Authorization Code with PKCE (mirrors
/// the iOS app's `GoogleAuthSession`, so no GoogleSignIn SDK is needed). Returns
/// a Google `id_token` which the backend verifies at POST /auth/google.
@MainActor
final class GoogleAuthSessionMac: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum GoogleAuthError: LocalizedError {
        case cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled:     return "Sign-in cancelled."
            case .failed(let m): return m
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func obtainIDToken() async throws -> String {
        let clientID = LumisBrand.googleClientID
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        let callbackScheme = reversed
        let redirectURI = reversed + ":/oauth2redirect"

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.s256(verifier)
        let state = Self.randomURLSafe(32)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]

        let callbackURL = try await present(url: comps.url!, scheme: callbackScheme)
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleAuthError.failed("Sign-in could not be verified.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.cancelled
        }
        return try await exchange(code: code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
    }

    // MARK: - Web auth

    private func present(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    cont.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    cont.resume(throwing: GoogleAuthError.failed(error?.localizedDescription ?? "Sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String, clientID: String, redirectURI: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = obj["id_token"] as? String else {
            throw GoogleAuthError.failed("Google did not return an identity token.")
        }
        return idToken
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL()
    }

    private static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
