import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var macVM: MacConnectionViewModel

    /// Opens the sidebar (replaces the old top-left wordmark).
    var onMenu: () -> Void = {}

    var body: some View {
        ZStack {
            LumisColors.parchment.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if macVM.connectionState == .linkedOffline {
                    MacOfflineBanner { Task { await macVM.reconnect() } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                LumisShapeView(state: vm.lumisState, containerSize: 260,
                               dimmed: macVM.connectionState == .linkedOffline)

                TranscriptionText(state: vm.lumisState,
                                  transcript: vm.transcript,
                                  response: vm.responseText)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)

                // Capture button: send the spoken command (visible once we have text).
                if vm.lumisState == .listening && !vm.transcript.isEmpty {
                    Button {
                        Haptics.medium()
                        vm.sendSpokenCommand()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LumisColors.carbonBlack)
                            .frame(width: 56, height: 56)
                            .background(LumisColors.powderBlue, in: Circle())
                    }
                    .padding(.top, 24)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send command")
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: vm.lumisState)
            .animation(.easeInOut(duration: 0.3), value: macVM.connectionState)

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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LumisColors.carbonBlack)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")
            Spacer()
            ConnectionStatusDot()
        }
        .padding(.horizontal, 20)
        .padding(.top, 44)
    }
}

/// Top-right connection status dot with popover.
private struct ConnectionStatusDot: View {
    @EnvironmentObject private var macVM: MacConnectionViewModel
    @State private var showPopover = false
    @State private var pulse = false

    private var color: Color {
        switch macVM.connectionState {
        case .linkedOnline: return LumisColors.powderBlue
        case .linkedOffline: return LumisColors.amber
        case .unlinked, .linking: return LumisColors.textTertiary
        }
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse && macVM.connectionState == .linkedOnline ? 1.4 : 1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
        .accessibilityLabel(statusText)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            Text(statusText)
                .font(LumisTypography.bodySmall)
                .foregroundStyle(LumisColors.carbonBlack)
                .padding(14)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var statusText: String {
        switch macVM.connectionState {
        case .linkedOnline: return "Connected to \(macVM.macName ?? "your Mac")"
        case .linkedOffline:
            let seen = macVM.lastSeen.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "a while ago"
            return "Mac is offline — last seen \(seen)"
        case .unlinked, .linking: return "No Mac linked — go to Settings to connect"
        }
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
                    .font(.system(size: 14))
                    .foregroundStyle(LumisColors.powderBlue.opacity(0.6))
            case .listening:
                AnimatedWords(text: transcript.isEmpty ? "Listening…" : transcript)
                    .foregroundStyle(LumisColors.carbonBlack)
            case .thinking:
                Text("Thinking…")
                    .font(.system(size: 14))
                    .foregroundStyle(LumisColors.powderBlue.opacity(thinkingPulse ? 0.8 : 0.4))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            thinkingPulse = true
                        }
                    }
            case .speaking:
                AnimatedWords(text: response)
                    .foregroundStyle(LumisColors.carbonBlack)
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
