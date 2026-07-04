import SwiftUI

/// Top-level gate: Splash while validating the stored token, then either the
/// auth flow (unauthenticated) or the main app (authenticated).
struct RootView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var minSplashElapsed = false

    #if DEBUG
    /// UI-screenshot hook (like LUMIS_NO_MIC): jump straight to the main app.
    private var uiPreview: Bool { ProcessInfo.processInfo.environment["LUMIS_UI_PREVIEW"] != nil }
    #else
    private var uiPreview: Bool { false }
    #endif

    var body: some View {
        Group {
            if uiPreview {
                MainTabView()
            } else if authVM.isLoading || !minSplashElapsed {
                SplashView()
                    .transition(.opacity)
            } else if !authVM.isAuthenticated {
                AuthFlowView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authVM.isLoading)
        .animation(.easeInOut(duration: 0.4), value: authVM.isAuthenticated)
        .animation(.easeInOut(duration: 0.4), value: minSplashElapsed)
        .task {
            // Validate the session while the splash shows (min 1.8s).
            async let bootstrap: Void = authVM.bootstrap()
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            minSplashElapsed = true
            await bootstrap
        }
    }
}
