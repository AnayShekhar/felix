import Foundation

/// Single source of truth for backend endpoints + app metadata.
/// Replace any hardcoded URL with `LumisConfig.backendURL` / `LumisConfig.websocketURL`.
struct LumisConfig {
    static let backendURL    = "https://lumis-production-b878.up.railway.app"
    static let websocketURL  = "wss://lumis-production-b878.up.railway.app/ws"
    static let appVersion    = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let buildNumber   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    /// Support address used by the "Send feedback" row in Settings.
    static let supportEmail  = "teamlumis1@gmail.com"

    /// iOS OAuth client ID from Google Cloud Console. Set this (and register the
    /// reversed-client-id URL scheme) to enable "Continue with Google".
    static let googleClientID = "955535830862-t9jp1lql7ert69up16jr27pj248f58fi.apps.googleusercontent.com"

    /// In-app legal links.
    static let privacyPolicyURL = "https://lumis.app/privacy"
    static let termsURL         = "https://lumis.app/terms"
}
