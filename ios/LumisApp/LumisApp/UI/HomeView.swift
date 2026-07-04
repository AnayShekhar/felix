import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var authVM: AuthViewModel

    /// Opens the sidebar (replaces the old top-left wordmark).
    var onMenu: () -> Void = {}

    /// New York serif greeting, shown above the mark when Lumis is idle. It
    /// fades out while a conversation is active so the transcript/response leads.
    private var greeting: String {
        LumisGreeting.current(name: authVM.currentUser?.name)
    }

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer()

                Text(greeting)
                    .font(LumisTypography.greeting)
                    .tracking(-0.5)
                    .foregroundStyle(LumisColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LumisSpacing.xxl)
                    .padding(.bottom, LumisSpacing.xxl)
                    .opacity(vm.lumisState == .idle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: vm.lumisState)
                    .accessibilityAddTraits(.isHeader)

                AnimatedLumisMark(state: vm.lumisState, speech: vm.speech,
                                  dimmed: false)

                TranscriptionText(state: vm.lumisState,
                                  transcript: vm.transcript,
                                  response: vm.responseText)
                    .padding(.top, LumisSpacing.xl)
                    .padding(.horizontal, LumisSpacing.xxl)

                // Capture button: send the spoken command (visible once we have text).
                if vm.lumisState == .listening && !vm.transcript.isEmpty {
                    Button {
                        Haptics.medium()
                        vm.sendSpokenCommand()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LumisColors.onTint)
                            .frame(width: 56, height: 56)
                            .background(LumisColors.tint, in: Circle())
                    }
                    .padding(.top, LumisSpacing.xl)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send command")
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: vm.lumisState)

            // Result card slides up above the tab bar.
            if let result = vm.lastResult {
                VStack {
                    Spacer()
                    LumisResultCard(result: result,
                                    onDismiss: { withAnimation { vm.lastResult = nil } },
                                    onOpen: result.deeplink.map { url in { UIApplication.shared.open(url) } })
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(.keyboard)
            }

            // Error toast.
            if let error = vm.errorMessage {
                VStack { Spacer(); ErrorToast(message: error) { vm.errorMessage = nil }.padding(.bottom, 100) }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.lastResult)
    }

    private var topBar: some View {
        HStack {
            Button { Haptics.light(); onMenu() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(LumisColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")
            Spacer()
            ConnectionStatusDot(ws: vm.ws)
        }
        .padding(.horizontal, LumisSpacing.screenMargin)
        .padding(.top, 44)
    }
}

/// Wraps the Lumis mark and observes the speech recognizer so the audio-reactive
/// listening animation gets the live mic level — without re-rendering all of
/// HomeView at audio rate.
private struct AnimatedLumisMark: View {
    let state: LumisState
    @ObservedObject var speech: SpeechRecognizer
    let dimmed: Bool

    var body: some View {
        LumisShapeView(
            state: state,
            containerSize: 260,
            audioLevel: state == .listening ? speech.inputLevel : 0,
            dimmed: dimmed
        )
    }
}

/// Top-right status dot with popover. Reflects the REAL account link status:
/// the backend WebSocket, plus the Chrome-extension cookie-sync freshness
/// (never / recent / stale) fetched from /connect/status.
private struct ConnectionStatusDot: View {
    @ObservedObject var ws: WebSocketClient
    @StateObject private var servicesVM = ConnectedServicesViewModel()
    @State private var showPopover = false
    @State private var pulse = false

    private var connected: Bool { ws.connected }

    private var dotColor: Color {
        guard connected else { return LumisColors.textTertiary }
        switch servicesVM.syncState {
        case .recentlySynced: return LumisColors.success
        case .stale:          return LumisColors.amber
        case .neverConnected: return LumisColors.tint
        }
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse && connected ? 1.5 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
        .task { await servicesVM.fetchStatus() }
        .accessibilityLabel(statusText)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: LumisSpacing.xs) {
                Text(statusText)
                    .font(LumisTypography.bodySmall)
                    .foregroundStyle(LumisColors.textPrimary)
                Text(servicesVM.syncState.detail)
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: 280)
            .presentationCompactAdaptation(.popover)
            .task { await servicesVM.fetchStatus() }
        }
    }

    private var statusText: String {
        guard connected else { return "Connecting to Lumis…" }
        return servicesVM.syncState.title
    }
}

/// State-driven hint / transcript / response text with per-word entrance.
private struct TranscriptionText: View {
    let state: LumisState
    let transcript: String
    let response: String
    @State private var thinkingPulse = false

    var body: some View {
        Group {
            switch state {
            case .idle:
                Text("Say \u{201C}Hey Lumis\u{201D}")
                    .font(.system(size: 17))
                    .foregroundStyle(LumisColors.textPrimary.opacity(0.4))
            case .listening:
                AnimatedWords(text: transcript.isEmpty ? "Listening…" : transcript)
                    .foregroundStyle(LumisColors.textPrimary)
            case .thinking:
                Text("Thinking…")
                    .font(.system(size: 17))
                    .foregroundStyle(LumisColors.textPrimary.opacity(thinkingPulse ? 0.7 : 0.45))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            thinkingPulse = true
                        }
                    }
            case .speaking:
                AnimatedWords(text: response)
                    .foregroundStyle(LumisColors.textPrimary)
            }
        }
        .font(.system(size: 17))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .lineLimit(3)
        .accessibilityLabel(transcript.isEmpty ? response : transcript)
    }
}

/// Renders text word-by-word, each fading + rising in, staggered.
private struct AnimatedWords: View {
    let text: String
    @State private var shown = 0

    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: 17))
                    .opacity(index < shown ? 1 : 0)
                    .offset(y: index < shown ? 0 : 4)
            }
        }
        .onChange(of: words.count) { _, count in animate(to: count) }
        .onAppear { animate(to: words.count) }
    }

    private func animate(to count: Int) {
        guard count > shown else { shown = count; return }
        for i in shown..<count {
            withAnimation(.easeOut(duration: 0.2).delay(Double(i - shown) * 0.05)) {
                shown = i + 1
            }
        }
    }
}
