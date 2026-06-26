import SwiftUI

/// Root of the redesigned iOS app: a 4-tab shell. Owns the shared runtime
/// objects (camera, speech, websocket, discovery, settings) and hands them to
/// the tabs. All core logic lives in CameraManager / SpeechRecognizer /
/// APIClient / WebSocketClient — this layer is presentation only.
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var speech = SpeechRecognizer()
    @StateObject private var ws = WebSocketClient()
    @StateObject private var discovery = MacDiscovery()
    @StateObject private var settings = AppSettings()
    @ObservedObject private var router = DeepLinkRouter.shared

    @State private var selection = 0
    @AppStorage("felix.onboardingComplete") private var onboardingComplete = false
    private let sessionID = "ios-\(UUID().uuidString.prefix(6))"

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }

    var body: some View {
        TabView(selection: $selection) {
            CameraTab(camera: camera, speech: speech, ws: ws,
                      discovery: discovery, settings: settings, sessionID: sessionID)
                .tabItem { Label("Camera", systemImage: "camera.viewfinder") }
                .tag(0)

            HistoryTab(ws: ws, settings: settings, discovery: discovery)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)

            MemoryTab(settings: settings, discovery: discovery)
                .tabItem { Label("Memory", systemImage: "brain") }
                .tag(2)

            SettingsTab(settings: settings, discovery: discovery, ws: ws)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.felix)
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .onChange(of: discovery.baseURL) { _, _ in reconnect() }
        .onChange(of: settings.backendOverride) { _, _ in reconnect() }
        .onChange(of: router.requestedTab) { _, tab in
            if let tab { selection = tab; router.requestedTab = nil }
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete)) {
            OnboardingView(settings: settings) {
                onboardingComplete = true
            }
        }
    }

    private func setup() {
        configureTabBarAppearance()
        speech.requestPermission()
        camera.start()
        discovery.start()
        speech.startListening()
        ws.connect(to: Config.wsURL(base: baseURL))
    }

    private func reconnect() {
        ws.connect(to: Config.wsURL(base: baseURL))
    }

    /// Opaque dark tab bar so it reads cleanly over the live camera feed.
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.04, alpha: 1.0)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
}
