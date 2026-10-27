import SwiftUI
import Combine

/// Central handler for `felix://` deep links (Phase 8).
///
/// The lock-screen widget and the share sheet open the app via custom URLs.
/// Views observe this singleton to react:
///   felix://capture  → jump to the Camera tab and arm listening.
///   felix://setup    → surface Mac-permission setup instructions (onboarding).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// Set when `felix://capture` fires. CameraTab consumes it on appear.
    @Published var autoCapture = false
    /// Set when `felix://setup` fires. Onboarding/Settings can present setup help.
    @Published var showSetup = false
    /// Tab the shell should switch to (0 = Camera). nil = no request.
    @Published var requestedTab: Int?

    private init() {}

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "felix" else { return }
        // Accept either felix://capture or felix:capture style hosts/paths.
        let target = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        switch target {
        case "capture":
            autoCapture = true
            requestedTab = 0
        case "setup":
            showSetup = true
        default:
            break
        }
    }
}
