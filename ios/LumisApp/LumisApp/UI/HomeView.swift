import SwiftUI

/// The main screen. Three states under one persistent branding top bar:
///
///   • Dormant   — the scribble mark idling, a mic affordance, and a "+"
///                 that unfolds into the text input. Nothing else.
///   • Listening — the scribble reacting to the user's live voice. No
///                 transcript, no spoken reply — the response is visual.
///   • Panels    — the request's live panel stack, filling everything
///                 below the top bar.
///
/// The top bar is branding only (logo slot + "Lumis") and never scrolls;
/// connection status lives exclusively in Settings.
struct HomeView: View {
    @EnvironmentObject private var vm: LumisViewModel

    /// Opens the sidebar (Past Chats).
    var onMenu: () -> Void = {}
    /// Opens the live camera (from the text bar's "+").
    var onCamera: () -> Void = {}

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

                // Sidebar toggle sits just beneath the wordmark bar, top-left.
                HStack {
                    Button {
                        Haptics.light()
                        onMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(LumisColors.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Past Chats")
                    Spacer()
                }
                .padding(.horizontal, LumisSpacing.sm)

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
    private var scribbleStage: some View {
        VStack(spacing: LumisSpacing.xl) {
            Spacer()
            ScribbleView(
                state: vm.lumisState,
                containerSize: 240,
                audioLevel: vm.lumisState == .listening ? vm.speech.inputLevel : 0
            )
            Spacer()
            Spacer().frame(height: 60)   // breathing room above the input bar
        }
        .frame(maxWidth: .infinity)
    }
}

/// The persistent branding bar: a reserved slot for the logo mark (no asset
/// yet) followed by the wordmark, SF Pro. Purely branding — no status, no
/// functional chrome — and it never scrolls.
private struct BrandingTopBar: View {
    var body: some View {
        HStack(spacing: LumisSpacing.sm) {
            // Logo slot — clearly defined, quiet, awaiting the real mark.
            LumisRadius.rect(LumisRadius.sm)
                .stroke(LumisColors.divider, lineWidth: 1)
                .frame(width: 26, height: 26)

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

/// The bottom affordances. Collapsed: a mic affordance and a "+". Tapping the
/// "+" unfolds the "Message Lumis." text bar (with its own "+" for the live
/// camera). Every path resolves into the same panel stack.
private struct LumisInputBar: View {
    @EnvironmentObject private var vm: LumisViewModel
    var onCamera: () -> Void

    @State private var expanded = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @Namespace private var barSpace

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if expanded {
                textBar
                    .matchedGeometryEffect(id: "bar", in: barSpace)
            } else {
                collapsedControls
                    .matchedGeometryEffect(id: "bar", in: barSpace)
            }
        }
        .padding(.horizontal, LumisSpacing.screenMargin)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canSend)
    }

    // MARK: Collapsed — mic + "+"

    private var collapsedControls: some View {
        HStack(spacing: LumisSpacing.lg) {
            Spacer()

            // Mic affordance: makes sure Lumis is listening for the wake word.
            Button {
                Haptics.light()
                vm.speech.requestPermission()
                vm.speech.startListening()
            } label: {
                Image(systemName: "mic")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(LumisColors.onTint)
                    .frame(width: 64, height: 64)
                    .background(LumisColors.tint, in: Circle())
            }
            .buttonStyle(.lumisPress)
            .accessibilityLabel("Listen for a voice request")

            // "+" — unfolds into the text input.
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    expanded = true
                }
                focused = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(LumisColors.textPrimary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.lumisPress)
            .accessibilityLabel("Type a message")

            Spacer()
        }
    }

    // MARK: Expanded — "Message Lumis." bar

    private var textBar: some View {
        HStack(spacing: LumisSpacing.sm) {
            // The bar's own "+": opens the live camera view.
            Button {
                Haptics.light()
                onCamera()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(LumisColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open camera")

            TextField("Message Lumis.", text: $text)
                .textFieldStyle(.plain)
                .font(LumisTypography.bodyLarge)
                .foregroundStyle(LumisColors.textPrimary)
                .tint(LumisColors.tint)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)

            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.callout.weight(.semibold))
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
                    focused = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        expanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LumisColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Close the message bar")
            }
        }
        .padding(.leading, LumisSpacing.md)
        .padding(.trailing, LumisSpacing.sm)
        .frame(height: 56)
        .glassEffect(.regular, in: Capsule())
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Haptics.medium()
        vm.send(image: nil, text: t)
        text = ""
        focused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            expanded = false
        }
    }
}
