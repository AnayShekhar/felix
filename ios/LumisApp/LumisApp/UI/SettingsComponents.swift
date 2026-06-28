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
                .foregroundStyle(LumisColors.carbonBlack.opacity(0.4))
                .padding(.leading, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(LumisColors.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LumisColors.divider, lineWidth: 1))
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
                Image(systemName: icon).foregroundStyle(LumisColors.powderBlue).frame(width: 22)
            }
            Text(title).font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.carbonBlack)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

extension View {
    func settingsRowPadding() -> some View { self.padding(.horizontal, 16).padding(.vertical, 13) }
    func settingsToggle() -> some View {
        self.font(LumisTypography.bodyLarge)
            .foregroundStyle(LumisColors.carbonBlack)
            .tint(LumisColors.powderBlue)
            .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Custom slider: Powder-Blue fill, white thumb with Powder-Blue border.
struct LumisSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LumisColors.carbonBlack.opacity(0.15)).frame(height: 4)
                Capsule().fill(LumisColors.powderBlue).frame(width: max(0, w * value), height: 4)
                Circle().fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(LumisColors.powderBlue, lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .offset(x: max(0, min(w - 22, w * value - 11)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, g.location.x / w))
            })
        }
        .frame(height: 22)
    }
}
