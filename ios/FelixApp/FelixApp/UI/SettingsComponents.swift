import SwiftUI

/// Apple-Settings-style grouped section. The rows retain the familiar inset
/// grouping and scanability of Settings, but sit on the same restrained native
/// material as the rest of Felix rather than on opaque gray cards.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.footer = footer; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(FelixTypography.caption)
                .foregroundStyle(FelixColors.textTertiary)
                .padding(.leading, FelixSpacing.lg)
                .padding(.bottom, 7)
            VStack(spacing: 0) {
                content()
            }
            .background(FelixColors.surface, in: FelixRadius.rect(FelixRadius.md))
            .felixGlass(in: FelixRadius.rect(FelixRadius.md))
            if let footer {
                Text(footer)
                    .font(FelixTypography.caption)
                    .foregroundStyle(FelixColors.textTertiary)
                    .padding(.horizontal, FelixSpacing.lg)
                    .padding(.top, 7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The uniform leading icon treatment for Settings rows — one size, one
/// corner radius, one neutral weight everywhere. Deliberately not tinted: the
/// slate blue remains an interaction signal, not a field of colored icons.
struct SettingsIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(FelixColors.textSecondary)
            .frame(width: 29, height: 29)
            .background(FelixColors.surfaceProminent,
                        in: FelixRadius.rect(7))
            .overlay(FelixRadius.rect(7).stroke(FelixColors.glassStroke, lineWidth: 0.5))
    }
}

/// One Settings row: optional uniform icon chip, title (+ optional subtitle),
/// trailing accessory. Constant 44pt-minimum height and padding rhythm so
/// every row in the app sits on the same grid.
struct SettingsRow<Accessory: View>: View {
    var icon: String?
    let title: String
    var subtitle: String?
    @ViewBuilder let accessory: () -> Accessory

    init(icon: String? = nil, title: String, subtitle: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.icon = icon; self.title = title; self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: FelixSpacing.md) {
            if let icon { SettingsIcon(systemName: icon) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(FelixTypography.bodyLarge)
                    .foregroundStyle(FelixColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(FelixTypography.caption)
                        .foregroundStyle(FelixColors.textSecondary)
                }
            }
            Spacer(minLength: FelixSpacing.sm)
            accessory()
        }
        .settingsRowPadding()
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Trailing detail text (the muted value on the right of a row, like
/// Apple's "On" / "Off" / account name).
struct SettingsDetailText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(FelixTypography.bodyMedium)
            .foregroundStyle(FelixColors.textSecondary)
    }
}

/// Trailing disclosure chevron for navigation rows.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.medium))
            .foregroundStyle(FelixColors.textTertiary)
    }
}

/// Hairline row separator, inset like Apple's — it starts at the text
/// column, never at the screen edge. Pass `hasIcon: true` for rows with a
/// leading icon chip so the inset clears it.
struct SettingsDivider: View {
    var hasIcon: Bool = false
    var body: some View {
        Rectangle()
            .fill(FelixColors.divider)
            .frame(height: 0.5)
            .padding(.leading, hasIcon ? FelixSpacing.lg + 29 + FelixSpacing.md
                                       : FelixSpacing.lg)
    }
}

extension View {
    func settingsRowPadding() -> some View {
        self.padding(.horizontal, FelixSpacing.lg)
            .padding(.vertical, 11)
    }
}
