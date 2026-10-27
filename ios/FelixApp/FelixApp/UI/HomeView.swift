import SwiftUI

/// The main screen. Three states under one small, centered navigation bar:
///
///   • Dormant   — the scribble mark idling and a "+" that unfolds into the
///                 text input. Nothing else. There is deliberately NO mic
///                 button: the wake word is the only way to start listening,
///                 and the scribble's two states are that entire interface.
///   • Listening — the scribble reacting to the user's live voice. No
///                 transcript, no spoken reply — the response is visual.
///   • Panels    — the request's live panel stack, filling everything
///                 below the top bar.
///
/// The page is intentionally not a chat transcript. The visual center is the
/// voice-reactive Felix mark; the composer is a deliberate fallback rather
/// than a competing primary action.
struct HomeView: View {
    @EnvironmentObject private var vm: FelixViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opens the sidebar (past chats).
    var onMenu: () -> Void = {}
    /// Opens the live camera (from the text bar's "+").
    var onCamera: () -> Void = {}
    /// The signed-in user's initials, shown in the profile button.
    var initials: String = "?"
    /// Opens Settings (the profile button is its sole entry point).
    var onProfile: () -> Void = {}

    private enum Mode: Equatable { case dormant, listening, panels }

    private var mode: Mode {
        if vm.currentChat != nil { return .panels }
        return vm.felixState == .listening ? .listening : .dormant
    }

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HomeHeader(onMenu: onMenu, initials: initials, onProfile: onProfile)
                    .padding(.horizontal, FelixSpacing.screenMargin)
                    .padding(.top, FelixSpacing.xs)

                // The content beneath the fixed header changes between states.
                ZStack {
                    if mode == .panels, let chat = vm.currentChat {
                        PanelStackView(
                            chat: chat,
                            onDismiss: chat.isFinished ? { vm.dismissCurrentChat() } : nil
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    } else {
                        scribbleStage
                            .transition(.asymmetric(
                                insertion: .scale(scale: 1.06).combined(with: .opacity),
                                removal: .scale(scale: 0.45).combined(with: .opacity)
                                    .combined(with: .offset(y: -48))
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82), value: mode)

            // Error toast — API failures always surface.
            if let error = vm.errorMessage {
                VStack {
                    Spacer()
                    ErrorToast(message: error) { vm.errorMessage = nil }
                        .padding(.bottom, 84)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FelixInputBar(onCamera: onCamera)
                .padding(.horizontal, FelixSpacing.screenMargin)
                .padding(.bottom, FelixSpacing.sm)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: vm.errorMessage)
    }

    /// Dormant + listening: the scribble mark, centered, voice-reactive.
    /// Waking on the wake word pops the whole mark up with a snappy,
    /// slightly-overshooting spring — paired with the Canvas-level energy
    /// surge and activation ring, the state change is impossible to miss.
    private var scribbleStage: some View {
        VStack(spacing: FelixSpacing.lg) {
            Spacer()
            Text(stageTitle)
                .font(FelixTypography.greeting.weight(.medium))
                .foregroundStyle(FelixColors.textPrimary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(stageSubtitle)
                .font(FelixTypography.bodyMedium)
                .foregroundStyle(FelixColors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            ScribbleView(
                state: vm.felixState,
                containerSize: 218,
                audioLevel: vm.felixState == .listening ? vm.speech.inputLevel : 0
            )
            .scaleEffect(vm.felixState == .listening ? 1.12 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6),
                       value: vm.felixState == .listening)
            Spacer()
            Spacer().frame(height: 42)   // breathing room above the composer
        }
        .padding(.horizontal, FelixSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    private var stageTitle: String {
        switch vm.felixState {
        case .idle: return greeting
        case .listening: return "I’m listening"
        case .thinking: return "Working on it"
        case .speaking: return "Here’s what I found"
        }
    }

    private var stageSubtitle: String {
        switch vm.felixState {
        case .idle: return "Say “Hey Felix” or type a request below."
        case .listening: return "Tell Felix what you’d like to get done."
        case .thinking: return "Felix is understanding your request and choosing the next step."
        case .speaking: return "Your result is ready."
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }
}

/// A single, balanced navigation row. Both utilities occupy the same 44pt
/// circle, keeping the brand precisely centered without a second layer of
/// chrome below it.
private struct HomeHeader: View {
    var onMenu: () -> Void
    var initials: String
    var onProfile: () -> Void

    var body: some View {
        HStack {
            Button {
                Haptics.light()
                onMenu()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FelixColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.felixPress)
            .felixGlass(in: Circle(), interactive: true)
            .accessibilityLabel("Open past chats")

            Spacer()

            HStack(spacing: FelixSpacing.xs) {
                FelixLogoMark(size: 21)
                Text("Felix")
                    .font(FelixTypography.titleMedium)
                    .foregroundStyle(FelixColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Felix")
            .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                Haptics.light()
                onProfile()
            } label: {
                Text(initials)
                    .font(FelixTypography.titleSmall)
                    .foregroundStyle(FelixColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.felixPress)
            .felixGlass(in: Circle(), interactive: true)
            .accessibilityLabel("Open settings")
        }
        .frame(height: 52)
    }
}

/// The bottom affordance: a single glass "+" that unfolds into the
/// "Message Felix." text bar (whose leading "+" opens the live camera).
/// Voice never starts here — the wake word is the only listening trigger.
///
/// The expansion is one continuous surface, not a view swap: the same glass
/// capsule morphs from a 52pt circle into the full-width bar (a capsule at
/// 52×52 IS a circle), so the material and geometry carry through the whole
/// gesture — the Dynamic-Island family of transition. The "+" stays anchored
/// at the leading edge and simply changes role (expand → camera), giving the
/// eye one element to track; the field and trailing control fade/scale in
/// behind the surface so the shape leads and the content follows.
private struct FelixInputBar: View {
    @EnvironmentObject private var vm: FelixViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onCamera: () -> Void

    #if DEBUG
    // UI-screenshot hook: start with the bar already expanded.
    @State private var expanded =
        ProcessInfo.processInfo.environment["FELIX_UI_BAR_EXPANDED"] != nil
    #else
    @State private var expanded = false
    #endif
    @State private var text = ""
    @FocusState private var focused: Bool

    /// Opening: eager, with a touch of overshoot — the bar should feel like
    /// it wants to open. Closing: same spring family, more damped, so it
    /// settles cleanly without wobble. Never a plain ease curve.
    private static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private static let closeSpring = Animation.spring(response: 0.38, dampingFraction: 0.88)

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: FelixSpacing.sm) {
            // The one anchored element: "+" expands the bar; once expanded,
            // the same button opens the live camera.
            Button {
                Haptics.light()
                if expanded {
                    onCamera()
                } else {
                    withAnimation(Self.openSpring) { expanded = true }
                    focused = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(FelixColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Open camera" : "Type a message")

            if expanded {
                TextField("Message Felix.", text: $text)
                    .textFieldStyle(.plain)
                    .font(FelixTypography.bodyLarge)
                    .foregroundStyle(FelixColors.textPrimary)
                    .tint(FelixColors.tint)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))

                if canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(FelixColors.onTint)
                            .frame(width: 34, height: 34)
                            .background(FelixColors.tint, in: Circle())
                    }
                    .buttonStyle(.felixPress)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send")
                } else {
                    Button {
                        Haptics.light()
                        collapse()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FelixColors.textSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Close the message bar")
                }
            }
        }
        .padding(.horizontal, FelixSpacing.sm)
        .frame(height: expanded ? 56 : 52)
        .frame(maxWidth: expanded ? .infinity : 52)
        .felixGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
        .shadow(color: FelixColors.shadow, radius: 10, y: 4)
        .animation(reduceMotion ? nil : (expanded ? Self.openSpring : Self.closeSpring), value: expanded)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: canSend)
    }

    private func collapse() {
        focused = false
        withAnimation(Self.closeSpring) { expanded = false }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Haptics.medium()
        vm.send(image: nil, text: t)
        text = ""
        collapse()
    }
}
