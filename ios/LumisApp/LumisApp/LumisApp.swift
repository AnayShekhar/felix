import SwiftUI

@main
struct LumisApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in DeepLinkRouter.shared.handle(url) }
        }
    }
}
