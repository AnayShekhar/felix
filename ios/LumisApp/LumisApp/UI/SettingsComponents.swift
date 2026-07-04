import SwiftUI

/// Settings section: an uppercase header over quietly divided rows. No card
/// border — hierarchy comes from whitespace and typography; the one stronger
/// treatment (a bordered surface) is reserved for the profile summary.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(LumisTypography.caption)
                .tracking(0.8)
                .foregroundStyle(LumisColors.textTertiary)
                .padding(.leading, LumisSpacing.lg)
                .padding(.bottom, LumisSpacing.sm)
            VStack(spacing: 0) {
                content()
            }
        }
    }
}

/// One row: optional leading icon, title, trailing accessory.
struct SettingsRow<Accessory: View>: View {
    let icon: String?
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).foregroundStyle(LumisColors.textSecondary).frame(width: 22)
            }
            Text(title).font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.textPrimary)
            Spacer()
            accessory()
        }
        .padding(.horizontal, LumisSpacing.lg).padding(.vertical, LumisSpacing.md)
        .contentShape(Rectangle())
    }
}

extension View {
    func settingsRowPadding() -> some View { self.padding(.horizontal, LumisSpacing.lg).padding(.vertical, LumisSpacing.md) }
}
