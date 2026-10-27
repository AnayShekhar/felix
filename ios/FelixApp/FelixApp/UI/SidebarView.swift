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
                    .font(FelixTypography.titleLarge)
                    .foregroundStyle(FelixColors.textPrimary)
                Spacer()
                Button {
                    Haptics.light()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FelixColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.felixPress)
                .felixGlass(in: Circle(), interactive: true)
                .accessibilityLabel("Close recents")
            }
            .padding(.horizontal, FelixSpacing.lg)
            .padding(.top, 56)
            .padding(.bottom, FelixSpacing.md)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if pastChats.chats.isEmpty {
                        VStack(alignment: .leading, spacing: FelixSpacing.xs) {
                                Text("Your requests live here")
                                    .font(FelixTypography.bodyMedium)
                                    .foregroundStyle(FelixColors.textPrimary)
                            Text("Ask Felix to do something and you can revisit the full result here.")
                                .font(FelixTypography.bodySmall)
                                .foregroundStyle(FelixColors.textSecondary)
                        }
                        .padding(.horizontal, FelixSpacing.xl)
                        .padding(.top, FelixSpacing.md)
                    } else {
                        ForEach(pastChats.chats) { chat in
                            Button {
                                Haptics.light()
                                onOpenChat(chat)
                            } label: {
                                PastChatRow(chat: chat)
                            }
                            .buttonStyle(.felixPress)
                        }
                    }
                }
                .padding(.horizontal, FelixSpacing.sm)
                .padding(.bottom, FelixSpacing.xl)
            }

            Spacer(minLength: 0)

            // One confident action at the bottom of the panel.
            Button {
                Haptics.light()
                onNewChat()
            } label: {
                HStack(spacing: FelixSpacing.sm) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.medium))
                    Text("New chat")
                        .font(FelixTypography.bodyMedium)
                }
                .foregroundStyle(FelixColors.background)
                .padding(.horizontal, FelixSpacing.lg)
                .frame(height: 44)
                .contentShape(Capsule())
                .background(FelixColors.textPrimary, in: Capsule())
            }
            .buttonStyle(.felixPress)
            .accessibilityLabel("Start a new chat")
            .padding(.horizontal, FelixSpacing.lg)
            .padding(.bottom, 44)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FelixColors.surface)
        .felixGlass(in: Rectangle())
        .clipShape(.rect(bottomTrailingRadius: 28, topTrailingRadius: 28))
        .ignoresSafeArea()
        .shadow(color: FelixColors.shadow, radius: 24, x: 8, y: 0)
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
                .font(FelixTypography.bodyMedium)
                .foregroundStyle(FelixColors.textPrimary)
                .lineLimit(1)
            Text(RelativeTime.friendly(chat.startedAt.timeIntervalSince1970)
                 + (failed ? " · didn't finish" : ""))
                .font(FelixTypography.caption)
                .foregroundStyle(FelixColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FelixSpacing.lg)
        .padding(.vertical, FelixSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
