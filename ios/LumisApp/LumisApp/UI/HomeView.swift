import SwiftUI

/// The main screen. Three states under one persistent branding top bar:
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
/// The top bar is branding only (logo slot + "Lumis") and never scrolls;
/// connection status lives exclusively in Settings.
struct HomeView: View {
    @EnvironmentObject private var vm: LumisViewModel

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
        return vm.lumisState == .listening ? .listening : .dormant
    }

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                BrandingTopBar()

                // Liquid Glass controls sit just beneath the wordmark bar:
                // sidebar toggle top-left, profile (opens Settings) top-right.
                HStack {
                    Button {
                        Haptics.light()
                        onMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                            .foregroundStyle(LumisColors.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Open past chats")

                    Spacer()

                    Button {
                        Haptics.light()
                        onProfile()
                    } label: {
                        Text(initials)
                            .font(LumisTypography.titleSmall)
                            .foregroundStyle(LumisColors.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Open settings")
                }
                .padding(.horizontal, LumisSpacing.screenMargin)

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
            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: mode)

            // Error toast — API failures always surface.
            if let error = vm.errorMessage {
                VStack {
                    Spacer()
                    ErrorToast(message: error) { vm.errorMessage = nil }
                        .padding(.bottom, 110)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            LumisInputBar(onCamera: onCamera)
                .padding(.bottom, LumisSpacing.md)
        }
        .animation(.easeInOut(duration: 0.3), value: vm.errorMessage)
    }

    /// Dormant + listening: the scribble mark, centered, voice-reactive.
    /// Waking on the wake word pops the whole mark up with a snappy,
    /// slightly-overshooting spring — paired with the Canvas-level energy
    /// surge and activation ring, the state change is impossible to miss.
    private var scribbleStage: some View {
        VStack(spacing: LumisSpacing.xl) {
            Spacer()
            ScribbleView(
                state: vm.lumisState,
                containerSize: 240,
                audioLevel: vm.lumisState == .listening ? vm.speech.inputLevel : 0
            )
            .scaleEffect(vm.lumisState == .listening ? 1.12 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.6),
                       value: vm.lumisState == .listening)
            Spacer()
            Spacer().frame(height: 60)   // breathing room above the input bar
        }
        .frame(maxWidth: .infinity)
    }
}

/// The persistent branding bar: the comet mark followed by the wordmark,
/// SF Pro. Purely branding — no status, no functional chrome — and it never
/// scrolls.
private struct BrandingTopBar: View {
    var body: some View {
        HStack(spacing: LumisSpacing.sm) {
            LumisLogoMark(size: 26)

            Text("Lumis")
                .font(LumisTypography.titleMedium)
                .foregroundStyle(LumisColors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, LumisSpacing.screenMargin)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lumis")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The bottom affordance: a single glass "+" that unfolds into the
/// "Message Lumis." text bar (whose leading "+" opens the live camera).
/// Voice never starts here — the wake word is the only listening trigger.
///
/// The expansion is one continuous surface, not a view swap: the same glass
/// capsule morphs from a 52pt circle into the full-width bar (a capsule at
/// 52×52 IS a circle), so the material and geometry carry through the whole
/// gesture — the Dynamic-Island family of transition. The "+" stays anchored
/// at the leading edge and simply changes role (expand → camera), giving the
/// eye one element to track; the field and trailing control fade/scale in
/// behind the surface so the shape leads and the content follows.
private struct LumisInputBar: View {
    @EnvironmentObject private var vm: LumisViewModel
    var onCamera: () -> Void

    #if DEBUG
    // UI-screenshot hook: start with the bar already expanded.
    @State private var expanded =
        ProcessInfo.processInfo.environment["LUMIS_UI_BAR_EXPANDED"] != nil
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
        HStack(spacing: LumisSpacing.sm) {
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
                    .foregroundStyle(LumisColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Open camera" : "Type a message")

            if expanded {
                TextField("Message Lumis.", text: $text)
                    .textFieldStyle(.plain)
                    .font(LumisTypography.bodyLarge)
                    .foregroundStyle(LumisColors.textPrimary)
                    .tint(LumisColors.tint)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))

                if canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(LumisColors.onTint)
                            .frame(width: 34, height: 34)
                            .background(LumisColors.tint, in: Circle())
                    }
                    .buttonStyle(.lumisPress)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send")
                } else {
                    Button {
                        Haptics.light()
                        collapse()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(LumisColors.textSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Close the message bar")
                }
            }
        }
        .padding(.horizontal, LumisSpacing.sm)
        .frame(height: expanded ? 56 : 52)
        .frame(maxWidth: expanded ? .infinity : 52)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .padding(.horizontal, LumisSpacing.screenMargin)
        .animation(expanded ? Self.openSpring : Self.closeSpring, value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canSend)
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
