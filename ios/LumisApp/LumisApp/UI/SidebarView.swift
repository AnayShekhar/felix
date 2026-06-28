import SwiftUI

/// Left side panel (liquid glass) opened by the home menu button. Shows the
/// recent actions and, bottom-left, a glass initials button that opens Settings.
struct SidebarView: View {
    let recent: [ActionHistoryItem]
    let initials: String
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lumis")
                .font(LumisTypography.titleLarge)
                .foregroundStyle(LumisColors.carbonBlack)
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 18)

            Text("RECENT")
                .font(LumisTypography.caption)
                .tracking(1.1)
                .foregroundStyle(LumisColors.textTertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if recent.isEmpty {
                        Text("Nothing yet. Ask Lumis to do something.")
                            .font(LumisTypography.bodySmall)
                            .foregroundStyle(LumisColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.top, 10)
                    } else {
                        ForEach(recent) { item in
                            RecentActionRow(item: item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Button { Haptics.light(); onSettings() } label: {
                HStack(spacing: 12) {
                    Text(initials)
                        .font(LumisTypography.titleSmall)
                        .foregroundStyle(LumisColors.carbonBlack)
                        .frame(width: 46, height: 46)
                        .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
                    Text("Settings")
                        .font(LumisTypography.bodyMedium)
                        .foregroundStyle(LumisColors.textSecondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color.clear.glassEffect(.regular, in: Rectangle())
        )
        .clipShape(.rect(bottomTrailingRadius: 28, topTrailingRadius: 28))
        .ignoresSafeArea()
        .shadow(color: .black.opacity(0.12), radius: 24, x: 8, y: 0)
    }
}

/// Compact recent-action row used in the sidebar.
private struct RecentActionRow: View {
    let item: ActionHistoryItem

    private var type: ActionType { ActionType.from(tool: item.tool_name) }
    private var failed: Bool { item.status == "error" }
    private var title: String { item.title ?? toolMeta(item.tool_name).label }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(type.tint.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: failed ? "exclamationmark" : type.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(failed ? LumisColors.destructive : type.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.carbonBlack)
                    .lineLimit(1)
                Text(RelativeTime.friendly(item.timestamp))
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
