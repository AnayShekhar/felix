import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Dependency-free "Sign in with Google" using ASWebAuthenticationSession +
/// OAuth 2.0 Authorization Code with PKCE. No GoogleSignIn SDK (the iOS app has
/// no third-party deps). Returns a Google `id_token` which the backend verifies.
///
/// Requires `LumisConfig.googleClientID` to be set (an iOS OAuth client created
/// in Google Cloud Console with reversed-client-id URL scheme registered).
@MainActor
final class GoogleAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum GoogleAuthError: LocalizedError {
        case notConfigured, cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google Sign-In isn't configured yet."
            case .cancelled:     return "Sign-in cancelled."
            case .failed(let m): return m
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    /// Runs the full flow and returns a verified-at-backend `id_token`.
    func obtainIDToken() async throws -> String {
        let clientID = LumisConfig.googleClientID
        guard !clientID.isEmpty else { throw GoogleAuthError.notConfigured }

        // Google iOS clients use the reversed client id as the redirect scheme.
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(reversed):/oauth2redirect"
        let callbackScheme = reversed

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

    // MARK: - Web auth presentation

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

    // MARK: - Token exchange

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
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
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
        return Data(bytes).base64URLEncoded()
    }

    private static func s256(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=")
        return set
    }()
}
