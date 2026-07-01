import SwiftUI
import AVFoundation

@main
struct LumisApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var macVM = MacConnectionViewModel()
    @StateObject private var lumisVM = LumisViewModel()

    init() {
        Self.configureAudioSession()
    }

    /// The ONE and ONLY audio-session configuration in the app. Configure it
    /// once on launch and never deactivate it — deactivating on TTS end and
    /// reactivating on listen start is what caused the 1–2s "dead silence" lag
    /// between Lumis finishing speaking and listening again (Part 2). Leaving the
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
                .environmentObject(macVM)
                .environmentObject(lumisVM)
                .preferredColorScheme(.light)   // Parchment theme is light-only
                .onOpenURL { url in DeepLinkRouter.shared.handle(url) }
        }
    }
}
