import SwiftUI
import AVFoundation

@main
struct FelixApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var felixVM = FelixViewModel()

    /// Appearance preference from Settings: System / Light / Dark.
    @AppStorage(FelixAppearance.storageKey) private var appearanceRaw = FelixAppearance.system.rawValue

    init() {
        #if DEBUG
        // UI-screenshot hook: skip audio-session activation (which triggers the
        // mic permission prompt) so verification shots aren't covered by it.
        if ProcessInfo.processInfo.environment["FELIX_NO_MIC"] != nil { return }
        #endif
        Self.configureAudioSession()
    }

    /// The ONE and ONLY audio-session configuration in the app. Configure it
    /// once on launch and never deactivate it — deactivating on TTS end and
    /// reactivating on listen start is what caused the 1–2s "dead silence" lag
    /// between Felix finishing speaking and listening again (Part 2). Leaving the
    /// play-and-record session active the whole time makes the mic instant.
    static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(felixVM)
                .preferredColorScheme((FelixAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                .onOpenURL { url in DeepLinkRouter.shared.handle(url) }
        }
    }
}
