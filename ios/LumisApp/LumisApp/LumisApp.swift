import SwiftUI

@main
struct LumisApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var macVM = MacConnectionViewModel()
    @StateObject private var lumisVM = LumisViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(macVM)
                .environmentObject(lumisVM)
                .preferredColorScheme(.light)   // Parchment theme is light-only
                .onOpenURL { url in DeepLinkRouter.shared.handle(url) }
        }
    }
}
