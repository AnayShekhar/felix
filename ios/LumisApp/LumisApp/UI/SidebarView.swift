import SwiftUI

/// Left side panel: recent requests, and nothing else. Each archived request is a
/// quiet row identified by its original text and a relative timestamp;
/// tapping one reopens its full panel stack (which can then be continued).
/// A Liquid Glass "New chat" button sits at the bottom, present only while
/// the sidebar is open. Settings is not reachable from here — the profile
/// button on the home screen is its sole entry point.
struct SidebarView: View {
    var onOpenChat: (ChatStack) -> Void
    var onNewChat: () -> Void
    var onClose: () -> Void

    /// Observed directly (not through the view model) so archiving a stack
    /// refreshes the list immediately.
    @ObservedObject var pastChats: PastChatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recents")
                    .font(LumisTypography.titleLarge)
                    .foregroundStyle(LumisColors.textPrimary)
                Spacer()
                Button {
                    Haptics.light()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LumisColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.lumisPress)
                .lumisGlass(in: Circle(), interactive: true)
                .accessibilityLabel("Close recents")
            }
            .padding(.horizontal, LumisSpacing.lg)
            .padding(.top, 56)
            .padding(.bottom, LumisSpacing.md)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if pastChats.chats.isEmpty {
                        VStack(alignment: .leading, spacing: LumisSpacing.xs) {
                                Text("Your requests live here")
                                    .font(LumisTypography.bodyMedium)
                                    .foregroundStyle(LumisColors.textPrimary)
                            Text("Ask Lumis to do something and you can revisit the full result here.")
                                .font(LumisTypography.bodySmall)
                                .foregroundStyle(LumisColors.textSecondary)
                        }
                        .padding(.horizontal, LumisSpacing.xl)
                        .padding(.top, LumisSpacing.md)
                    } else {
                        ForEach(pastChats.chats) { chat in
                            Button {
                                Haptics.light()
                                onOpenChat(chat)
                            } label: {
                                PastChatRow(chat: chat)
                            }
                            .buttonStyle(.lumisPress)
                        }
                    }
                }
                .padding(.horizontal, LumisSpacing.sm)
                .padding(.bottom, LumisSpacing.xl)
            }

            Spacer(minLength: 0)

            // One confident action at the bottom of the panel.
            Button {
                Haptics.light()
                onNewChat()
            } label: {
                HStack(spacing: LumisSpacing.sm) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.medium))
                    Text("New chat")
                        .font(LumisTypography.bodyMedium)
                }
                .foregroundStyle(LumisColors.background)
                .padding(.horizontal, LumisSpacing.lg)
                .frame(height: 44)
                .contentShape(Capsule())
                .background(LumisColors.textPrimary, in: Capsule())
            }
            .buttonStyle(.lumisPress)
            .accessibilityLabel("Start a new chat")
            .padding(.horizontal, LumisSpacing.lg)
            .padding(.bottom, 44)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LumisColors.surface)
        .lumisGlass(in: Rectangle())
        .clipShape(.rect(bottomTrailingRadius: 28, topTrailingRadius: 28))
        .ignoresSafeArea()
        .shadow(color: LumisColors.shadow, radius: 24, x: 8, y: 0)
    }
}

/// One past chat: the original request as the title, plus when it happened.
/// No borders, no cards — quiet rows with generous spacing.
private struct PastChatRow: View {
    let chat: ChatStack

    private var failed: Bool {
        chat.panels.last { $0.isFinal }?.state == .failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chat.request)
                .font(LumisTypography.bodyMedium)
                .foregroundStyle(LumisColors.textPrimary)
                .lineLimit(1)
            Text(RelativeTime.friendly(chat.startedAt.timeIntervalSince1970)
                 + (failed ? " · didn't finish" : ""))
                .font(LumisTypography.caption)
                .foregroundStyle(LumisColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LumisSpacing.lg)
        .padding(.vertical, LumisSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
