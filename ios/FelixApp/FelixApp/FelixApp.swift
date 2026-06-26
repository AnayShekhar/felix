import SwiftUI

@main
struct FelixApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in DeepLinkRouter.shared.handle(url) }
        }
    }
}
