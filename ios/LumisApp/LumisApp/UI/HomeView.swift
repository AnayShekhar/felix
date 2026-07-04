import SwiftUI

/// Home, laid out to the reference mockup: a centered state title in the top
/// bar (menu left, new-conversation right), the Lumis mark on a raised circular
/// disc, a wake-word pill, a Chat History / Transcript segmented control with
/// recent-action chips + See All, and the "Continue conversation" bar pinned to
/// the bottom (ChatBarView, overlaid by MainTabView). Adapts to light/dark via
/// the LumisColors tokens.
struct HomeView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var authVM: AuthViewModel

    /// Opens the sidebar (replaces the old top-left wordmark).
    var onMenu: () -> Void = {}

    @State private var recent: [ActionHistoryItem] = []
    @State private var showHistory = false

    private var greeting: String {
        LumisGreeting.current(name: authVM.currentUser?.name)
    }

    /// Centered top-bar title — the assistant's live state, like the mockup.
    private var stateTitle: String {
        switch vm.lumisState {
        case .idle:      return "Lumis"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Speaking"
        }
    }

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: LumisSpacing.md)

                // Serif greeting above the mark while idle; the transcript
                // takes over once a conversation starts.
                Text(greeting)
                    .font(LumisTypography.greeting)
                    .tracking(-0.5)
                    .foregroundStyle(LumisColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LumisSpacing.xxl)
                    .opacity(vm.lumisState == .idle ? 1 : 0)
                    .frame(height: 44)
                    .animation(.easeInOut(duration: 0.4), value: vm.lumisState)
                    .accessibilityAddTraits(.isHeader)

                OrbHero(state: vm.lumisState, speech: vm.speech)
                    .padding(.top, LumisSpacing.md)

                TranscriptionText(state: vm.lumisState,
                                  transcript: vm.transcript,
                                  response: vm.responseText)
                    .padding(.top, LumisSpacing.lg)
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
                    .padding(.top, LumisSpacing.md)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send command")
                } else {
                    WakeWordPill()
                        .padding(.top, LumisSpacing.lg)
                }

                Spacer(minLength: LumisSpacing.lg)

                RecentStrip(recent: recent, transcript: vm.transcript,
                            response: vm.responseText,
                            onSeeAll: { showHistory = true })
                    .padding(.bottom, 96)   // clears the chat bar overlay
            }
            .animation(.easeInOut(duration: 0.3), value: vm.lumisState)

            // Result card slides up above the chat bar.
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
        .sheet(isPresented: $showHistory) { HistoryView() }
        .task { await loadRecent() }
        .onChange(of: vm.lastResult) { _, _ in Task { await loadRecent() } }
    }

    private func loadRecent() async {
        if let fetched = try? await APIClient.history(baseURL: LumisConfig.backendURL) {
            recent = Array(fetched.prefix(12))
        }
    }

    // MARK: - Top bar (menu · state title + status dot · new conversation)

    private var topBar: some View {
        ZStack {
            HStack(spacing: LumisSpacing.sm) {
                ConnectionStatusDot(ws: vm.ws)
                Text(stateTitle)
                    .font(LumisTypography.titleMedium)
                    .foregroundStyle(LumisColors.textPrimary)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)

            HStack {
                TopBarButton(icon: "line.3.horizontal", label: "Open menu") {
                    Haptics.light(); onMenu()
                }
                Spacer()
                TopBarButton(icon: "square.and.pencil", label: "New conversation") {
                    Haptics.light()
                    withAnimation {
                        vm.transcript = ""
                        vm.responseText = ""
                        vm.lastResult = nil
                    }
                }
            }
        }
        .padding(.horizontal, LumisSpacing.screenMargin)
        .padding(.top, 44)
    }
}

/// 44pt glass-square icon button used at both ends of the top bar.
private struct TopBarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LumisColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(LumisColors.surface, in: RoundedRectangle(cornerRadius: LumisRadius.md))
                .overlay(RoundedRectangle(cornerRadius: LumisRadius.md)
                    .stroke(LumisColors.divider, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The Lumis mark seated on a raised circular disc, like the mockup's orb —
/// a soft radial gradient off the background with a hairline rim and shadow.
private struct OrbHero: View {
    let state: LumisState
    @ObservedObject var speech: SpeechRecognizer

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LumisColors.surface.opacity(0.9), LumisColors.surface.opacity(0.25)],
                        center: .init(x: 0.38, y: 0.3), startRadius: 10, endRadius: 220
                    )
                )
                .background(Circle().fill(LumisColors.background))
                .overlay(Circle().stroke(LumisColors.divider, lineWidth: 1))
                .shadow(color: LumisColors.shadow, radius: 24, y: 10)
                .frame(width: 250, height: 250)

            LumisShapeView(
                state: state,
                containerSize: 210,
                audioLevel: state == .listening ? speech.inputLevel : 0
            )
        }
        .accessibilityHidden(true)   // LumisShapeView carries the state label
    }
}

/// The pill under the orb (mockup's "Main Language · Auto-Detect"), wired to a
/// REAL setting: the "Hey Lumis" wake word toggle.
private struct WakeWordPill: View {
    @EnvironmentObject private var vm: LumisViewModel
    @AppStorage(LumisViewModel.wakeWordKey) private var wakeWord = true

    var body: some View {
        Button {
            Haptics.light()
            wakeWord.toggle()
            vm.setWakeWord(wakeWord)
        } label: {
            HStack(spacing: LumisSpacing.sm) {
                Image(systemName: wakeWord ? "waveform" : "waveform.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LumisColors.tint)
                Text("Hey Lumis")
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.textPrimary)
                Text(wakeWord ? "On" : "Off")
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LumisColors.textTertiary)
            }
            .padding(.horizontal, LumisSpacing.lg)
            .frame(height: 40)
            .background(LumisColors.surface, in: Capsule())
            .overlay(Capsule().stroke(LumisColors.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hey Lumis wake word, \(wakeWord ? "on" : "off")")
        .accessibilityHint("Double-tap to toggle")
    }
}

/// The bottom section from the mockup: a Chat History / Transcript segmented
/// pill control, then a horizontally scrolling row of recent-action chips with
/// a See All button (opens full History).
private struct RecentStrip: View {
    let recent: [ActionHistoryItem]
    let transcript: String
    let response: String
    var onSeeAll: () -> Void

    private enum Tab: String, CaseIterable { case history = "Chat History", transcript = "Transcript" }
    @State private var tab: Tab = .history

    var body: some View {
        VStack(spacing: LumisSpacing.md) {
            // Segmented pills
            HStack(spacing: LumisSpacing.sm) {
                ForEach(Tab.allCases, id: \.self) { t in
                    let active = tab == t
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
                    } label: {
                        Text(t.rawValue)
                            .font(LumisTypography.titleSmall)
                            .foregroundStyle(active ? LumisColors.onTint : LumisColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(active ? LumisColors.tint : LumisColors.surface, in: Capsule())
                            .overlay(Capsule().stroke(active ? .clear : LumisColors.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, LumisSpacing.screenMargin)

            switch tab {
            case .history:
                chipsRow
            case .transcript:
                Text(liveTranscript)
                    .font(LumisTypography.bodySmall)
                    .foregroundStyle(LumisColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
                    .padding(.horizontal, LumisSpacing.screenMargin)
            }
        }
    }

    private var liveTranscript: String {
        if !transcript.isEmpty { return "You: \(transcript)" }
        if !response.isEmpty { return "Lumis: \(response)" }
        return "Nothing yet — say \u{201C}Hey Lumis\u{201D} or type below."
    }

    @ViewBuilder
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LumisSpacing.sm) {
                if recent.isEmpty {
                    Text("Your recent actions will show up here.")
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.textTertiary)
                        .frame(height: 36)
                } else {
                    ForEach(recent.prefix(6)) { item in
                        Button(action: onSeeAll) {
                            Text(item.title ?? toolMeta(item.tool_name).label)
                                .font(LumisTypography.bodySmall)
                                .foregroundStyle(LumisColors.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, LumisSpacing.lg)
                                .frame(height: 36)
                                .background(LumisColors.surface, in: Capsule())
                                .overlay(Capsule().stroke(LumisColors.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: onSeeAll) {
                    Text("See All")
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.textPrimary)
                        .padding(.horizontal, LumisSpacing.lg)
                        .frame(height: 36)
                        .background(.clear, in: Capsule())
                        .overlay(Capsule().stroke(LumisColors.textSecondary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all history")
            }
            .padding(.horizontal, LumisSpacing.screenMargin)
        }
    }
}

/// Status dot next to the top-bar title. Reflects the REAL account link:
/// the backend WebSocket plus Chrome-extension cookie-sync freshness
/// (never / recent / stale) from /connect/status.
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
                .frame(width: 8, height: 8)
                .scaleEffect(pulse && connected ? 1.4 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                .frame(width: 24, height: 24)   // comfortable tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
