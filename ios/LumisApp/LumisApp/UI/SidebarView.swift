import SwiftUI

/// Left side panel: Past Chats. A calm, generously spaced list — the profile
/// mark at the top (opens Settings), then each archived request identified by
/// its original text and a relative timestamp. Tapping one reopens its full
/// panel stack exactly as it finished.
struct SidebarView: View {
    let initials: String
    var name: String = ""
    var email: String = ""
    var onSettings: () -> Void
    var onOpenChat: (ChatStack) -> Void

    /// Observed directly (not through the view model) so archiving a stack
    /// refreshes the list immediately.
    @ObservedObject var pastChats: PastChatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile — consistently at the top, part of the same list
            // structure, always in the same place however far the list scrolls.
            Button { Haptics.light(); onSettings() } label: {
                HStack(spacing: LumisSpacing.md) {
                    Text(initials)
                        .font(LumisTypography.titleSmall)
                        .foregroundStyle(LumisColors.onTint)
                        .frame(width: 40, height: 40)
                        .background(LumisColors.tint, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name.isEmpty ? "Settings" : name)
                            .font(LumisTypography.titleSmall)
                            .foregroundStyle(LumisColors.textPrimary)
                            .lineLimit(1)
                        if !email.isEmpty {
                            Text(email)
                                .font(LumisTypography.caption)
                                .foregroundStyle(LumisColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, LumisSpacing.lg)
                .padding(.vertical, LumisSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.lumisPress)
            .accessibilityLabel("Open Settings")
            .padding(.top, 56)

            Divider().overlay(LumisColors.divider)
                .padding(.horizontal, LumisSpacing.lg)

            Text("Past Chats")
                .font(LumisTypography.caption)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(LumisColors.textTertiary)
                .padding(.horizontal, LumisSpacing.xl)
                .padding(.top, LumisSpacing.lg)
                .padding(.bottom, LumisSpacing.xs)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if pastChats.chats.isEmpty {
                        Text("Nothing yet. Ask Lumis to do something.")
                            .font(LumisTypography.bodySmall)
                            .foregroundStyle(LumisColors.textSecondary)
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
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color.clear.glassEffect(.regular, in: Rectangle())
        )
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
