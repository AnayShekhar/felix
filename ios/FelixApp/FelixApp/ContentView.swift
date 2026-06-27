import SwiftUI
import UIKit

/// Phase 9 — the root compositor. No tab bar: a single immersive screen with the
/// Moonstone orb at its center. Layers (back to front): #070B12 background, the
/// ambient glow, the camera feed (only during visual capture), the orb, the live
/// transcription, the result card / captions, and the floating nav buttons.
///
/// All core logic is unchanged — CameraManager / SpeechRecognizer / APIClient /
/// WebSocketClient drive everything; this layer only presents and routes.
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var speech = SpeechRecognizer()
    @StateObject private var ws = WebSocketClient()
    @StateObject private var discovery = MacDiscovery()
    @StateObject private var settings = AppSettings()
    @StateObject private var amplitude = VoiceAmplitudeTracker()
    @ObservedObject private var router = DeepLinkRouter.shared

    @AppStorage("felix.onboardingComplete") private var onboardingComplete = false
    private let sessionID = "ios-\(UUID().uuidString.prefix(6))"

    // Orb + flow state.
    @State private var orbState: OrbState = .idle
    @State private var capturing = false        // visual-context capture in progress
    @State private var cameraVisible = false     // camera feed faded in
    @State private var sending = false

    // Presentation.
    @State private var resultCard: StepResult?
    @State private var contentSheet: StepResult?
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var gearVisible = false
    @State private var errorMessage: String?
    @State private var showCancelled = false
    @State private var thinkingCaption = false
    @State private var pulseToken = 0

    // Auto-send (Phase 1) + card timing.
    @State private var pendingSend: DispatchWorkItem?
    @State private var cardDismiss: DispatchWorkItem?
    @State private var longTask = false

    private var baseURL: String { settings.resolvedBaseURL(discovery: discovery) }
    private var busy: Bool { sending || ws.working }
    private var orbCompact: Bool { cameraVisible || resultCard != nil }

    /// Phase 1 visual-context trigger words.
    private static let visualTriggers: [String] = [
        "this", "here", "that", "what is", "read this", "scan", "look at",
        "show me", "add this", "turn this", "what does this", "how much",
        "who is", "translate this", "summarize this",
    ]
    private func needsVisualContext(_ command: String) -> Bool {
        let lower = command.lowercased()
        return Self.visualTriggers.contains { lower.contains($0) }
    }

    var body: some View {
        GeometryReader { geo in
            let orbY = geo.size.height * 0.4
            ZStack {
                FelixColor.background.ignoresSafeArea()

                FelixGlowView(state: orbState, amplitude: amplitude,
                              centerYFraction: orbCompact ? 0.12 : 0.4)

                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .opacity(cameraVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: cameraVisible)
                    .allowsHitTesting(false)

                FelixOrbView(state: orbState, amplitude: amplitude, pulseToken: pulseToken)
                    .scaleEffect(orbCompact ? 0.55 : 1)
                    .position(x: geo.size.width / 2,
                              y: orbCompact ? geo.safeAreaInsets.top + 40 : orbY)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orbCompact)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.8).onEnded { _ in revealGear() }
                    )

                belowOrb
                    .frame(width: geo.size.width)
                    .position(x: geo.size.width / 2, y: orbY + 150)

                if gearVisible {
                    gearButton.position(x: geo.size.width / 2, y: orbY - 150)
                }

                if let card = resultCard {
                    VStack { Spacer(); ResultCard(result: card) { dismissCard() }.padding(.bottom, 120) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showCancelled {
                    Text("Cancelled")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .frostedCard(cornerRadius: 20)
                        .position(x: geo.size.width / 2, y: orbY)
                        .transition(.opacity)
                }

                VStack { Spacer(); FelixNavBar(
                    cameraActive: cameraVisible || capturing,
                    historyActive: showHistory,
                    onCamera: { triggerManualCamera() },
                    onHistory: { showHistory = true }
                ) }

                ShakeDetector { cancelPendingSend() }.allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { if gearVisible { withAnimation { gearVisible = false } } }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .onChange(of: discovery.baseURL) { _, _ in reconnect() }
        .onChange(of: settings.backendOverride) { _, _ in reconnect() }
        .onChange(of: speech.phase) { _, phase in handlePhase(phase) }
        .onChange(of: speech.command) { _, cmd in scheduleAutoSend(for: cmd) }
        .onChange(of: ws.working) { _, _ in refreshOrbState() }
        .onChange(of: ws.speaking) { _, speaking in handleSpeaking(speaking) }
        .onChange(of: ws.latest?.id) { _, _ in handleResult() }
        .onChange(of: orbState) { _, s in
            thinkingCaption = false
            if s == .thinking {
                // Caption fades in after 0.5s.
                let work = DispatchWorkItem { if orbState == .thinking { withAnimation { thinkingCaption = true } } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }
        .onChange(of: router.autoCapture) { _, on in if on { consumeAutoCapture() } }
        .sheet(item: $contentSheet) { result in
            ContentResultSheet(result: result)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistory) {
            HistoryTab(ws: ws, settings: settings, discovery: discovery)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, discovery: discovery, ws: ws)
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete)) {
            OnboardingView(settings: settings) { onboardingComplete = true }
        }
    }

    // MARK: - Below-orb stack (transcription, captions)

    @ViewBuilder
    private var belowOrb: some View {
        VStack(spacing: 12) {
            if thinkingCaption {
                Text("Thinking…")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.opacity)
            }
            TranscriptionView(text: speech.command, visible: speech.phase == .hearing)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(FelixColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
        }
    }

    private var gearButton: some View {
        Button {
            withAnimation { gearVisible = false }
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .frostedCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Setup

    private func setup() {
        speech.requestPermission()
        camera.start()
        discovery.start()
        speech.startListening()
        amplitude.start()
        ws.connect(to: Config.wsURL(base: baseURL))
        // Pulse the orb on each TTS word boundary (Phase 4 SPEAKING).
        ws.onWordBoundary = { pulseToken &+= 1 }
    }

    private func reconnect() { ws.connect(to: Config.wsURL(base: baseURL)) }

    private func revealGear() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { gearVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { gearVisible = false }
        }
    }

    private func consumeAutoCapture() {
        guard router.autoCapture else { return }
        router.autoCapture = false
        speech.startListening()
    }

    // MARK: - Orb state machine

    private func handlePhase(_ phase: SpeechRecognizer.Phase) {
        if phase == .hearing {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation { orbState = .wake }
            // Settle from WAKE into LISTENING shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if speech.phase == .hearing { refreshOrbState() }
            }
        } else {
            pendingSend?.cancel(); pendingSend = nil
            refreshOrbState()
        }
    }

    private func handleSpeaking(_ speaking: Bool) {
        refreshOrbState()
        if !speaking, resultCard != nil { scheduleCardDismiss(after: 1.5) }
    }

    /// Recompute the orb state from current inputs (transient WAKE/ERROR aside).
    private func refreshOrbState() {
        if orbState == .error { return }       // let the error animation finish
        let next: OrbState
        if capturing { next = .camera }
        else if ws.speaking { next = .speaking }
        else if busy { next = .thinking }
        else if speech.phase == .hearing { next = .listening }
        else { next = .idle }
        withAnimation(.easeInOut(duration: 0.25)) { orbState = next }
    }

    // MARK: - Result handling

    private func handleResult() {
        guard !ws.working, let latest = ws.latest else { return }

        if latest.status == "error" {
            withAnimation { orbState = .error; errorMessage = latest.message ?? "Something went wrong." }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { refreshOrbState() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { errorMessage = nil } }
            return
        }

        if ResultPresentation.usesSheet(latest) {
            contentSheet = latest
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { resultCard = latest }
            // Auto-dismiss after 5s, unless Felix is mid-speech (held until it ends).
            if !ws.speaking { scheduleCardDismiss(after: 5) }
        }
    }

    private func scheduleCardDismiss(after seconds: Double) {
        cardDismiss?.cancel()
        let work = DispatchWorkItem { dismissCard() }
        cardDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func dismissCard() {
        cardDismiss?.cancel(); cardDismiss = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { resultCard = nil }
    }

    // MARK: - Auto-send (Phase 1, moved into the compositor)

    private func scheduleAutoSend(for command: String) {
        pendingSend?.cancel()
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty, speech.phase == .hearing else { return }
        let work = DispatchWorkItem {
            pendingSend = nil
            send(command: trimmed, withImage: needsVisualContext(trimmed))
        }
        pendingSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    private func cancelPendingSend() {
        guard pendingSend != nil else { return }
        pendingSend?.cancel(); pendingSend = nil
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        speech.reset()
        withAnimation { showCancelled = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showCancelled = false } }
    }

    private func triggerManualCamera() {
        let cmd = speech.command.trimmingCharacters(in: .whitespacesAndNewlines)
        send(command: cmd.isEmpty ? "What is this?" : cmd, withImage: true)
    }

    // MARK: - Send

    private func send(command: String, withImage: Bool) {
        guard !busy else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task { @MainActor in
            var image: UIImage?
            if withImage {
                // CAMERA ACTIVE: feed fades in, settle for autofocus, capture silently.
                capturing = true
                refreshOrbState()
                withAnimation { cameraVisible = true }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                image = await camera.capturePhoto()
                withAnimation { cameraVisible = false }
                capturing = false
            }

            sending = true
            refreshOrbState()    // → THINKING
            defer { sending = false }
            if longTask {
                _ = try? await APIClient.createTask(instruction: trimmed,
                                                    sessionID: sessionID, baseURL: baseURL)
            } else {
                _ = try? await APIClient.ingest(image: image, voiceText: trimmed,
                                                sessionID: sessionID, baseURL: baseURL)
            }
            speech.reset()
            refreshOrbState()
        }
    }
}

#Preview {
    ContentView()
}
