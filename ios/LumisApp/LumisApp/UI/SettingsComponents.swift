import SwiftUI

/// Grouped section with an uppercase header.
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
                .foregroundStyle(LumisColors.textPrimary.opacity(0.5))
                .padding(.leading, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(LumisColors.surface, in: RoundedRectangle(cornerRadius: LumisRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: LumisRadius.lg).stroke(LumisColors.divider, lineWidth: 1))
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
                Image(systemName: icon).foregroundStyle(LumisColors.tint).frame(width: 22)
            }
            Text(title).font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.textPrimary)
            Spacer()
            accessory()
        }
        .padding(.horizontal, LumisSpacing.lg).padding(.vertical, 13)
    }
}

extension View {
    func settingsRowPadding() -> some View { self.padding(.horizontal, LumisSpacing.lg).padding(.vertical, 13) }
}
