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
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .opacity(vm.lumisState == .idle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: vm.lumisState)
                    .accessibilityAddTraits(.isHeader)

                AnimatedLumisMark(state: vm.lumisState, speech: vm.speech,
                                  dimmed: false)

                TranscriptionText(state: vm.lumisState,
                                  transcript: vm.transcript,
                                  response: vm.responseText)
                    .padding(.top, 24)
                    .padding(.horizontal, 32)

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
                    .padding(.top, 24)
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
        .padding(.horizontal, 20)
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

/// Top-right connection status dot with popover — reflects the live backend
/// WebSocket connection (Lumis is a cloud service; there is no Mac to link).
private struct ConnectionStatusDot: View {
    @ObservedObject var ws: WebSocketClient
    @State private var showPopover = false
    @State private var pulse = false

    private var connected: Bool { ws.connected }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Circle()
                .fill(connected ? LumisColors.tint : LumisColors.textTertiary)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse && connected ? 1.5 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
        .accessibilityLabel(statusText)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            Text(statusText)
                .font(LumisTypography.bodySmall)
                .foregroundStyle(LumisColors.textPrimary)
                .padding(14)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var statusText: String {
        connected ? "Connected to Lumis" : "Connecting to Lumis…"
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
