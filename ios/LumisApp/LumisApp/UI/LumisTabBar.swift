import SwiftUI

/// Custom liquid-glass bottom tab bar (the native TabView bar can't be styled
/// this way). 4 tabs; active tab shows a Powder-Blue icon + label + dot.
struct LumisTabBar: View {
    @Binding var selected: LumisTab
    var onSelect: (LumisTab) -> Void
    @Namespace private var dot

    private struct Item { let tab: LumisTab; let title: String; let icon: String; let iconFill: String }
    private let items: [Item] = [
        .init(tab: .home,     title: "Home",     icon: "waveform.circle", iconFill: "waveform.circle.fill"),
        .init(tab: .history,  title: "History",  icon: "clock",           iconFill: "clock.fill"),
        .init(tab: .camera,   title: "Camera",   icon: "camera",          iconFill: "camera.fill"),
        .init(tab: .settings, title: "Settings", icon: "gearshape",       iconFill: "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab.rawValue) { item in
                button(item)
            }
        }
        .frame(height: 49)
        .padding(.bottom, 34)            // sit above the home indicator
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LumisColors.parchment.opacity(0.4)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LumisColors.carbonBlack.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func button(_ item: Item) -> some View {
        let active = selected == item.tab
        return Button {
            Haptics.light()
            onSelect(item.tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? item.iconFill : item.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(active ? LumisColors.powderBlue : LumisColors.carbonBlack.opacity(0.3))
                if active {
                    Text(item.title)
                        .font(LumisTypography.captionMedium)
                        .foregroundStyle(LumisColors.powderBlue)
                }
                ZStack {
                    if active {
                        Circle()
                            .fill(LumisColors.powderBlue)
                            .frame(width: 4, height: 4)
                            .matchedGeometryEffect(id: "activeDot", in: dot)
                    } else {
                        Circle().fill(.clear).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }
}
