import Foundation

/// Single source of truth for backend endpoints + app metadata.
/// Replace any hardcoded URL with `LumisConfig.backendURL` / `LumisConfig.websocketURL`.
struct LumisConfig {
    static let backendURL    = "https://lumis-production-b878.up.railway.app"
    static let websocketURL  = "wss://lumis-production-b878.up.railway.app/ws"
    static let appVersion    = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let buildNumber   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    /// Support address used by the "Send feedback" row in Settings.
    static let supportEmail  = "support@lumis.app"
}
