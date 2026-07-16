import SwiftUI

/// Full-width filled button: the app's one confident, high-contrast action.
struct LumisPrimaryButton: View {
    let title: String
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled && !loading { action() } }) {
            ZStack {
                if loading {
                    ProgressView().tint(LumisColors.background)
                } else {
                    Text(title).font(LumisTypography.titleMedium)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(LumisColors.textPrimary)
            .foregroundStyle(LumisColors.background)
            .clipShape(LumisRadius.rect(LumisRadius.lg))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.lumisPress)
        .disabled(!enabled || loading)
        .accessibilityLabel(title)
    }
}

/// Full-width outlined button: Carbon Black border + text, optional leading icon.
struct LumisSecondaryButton<Leading: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading()
                Text(title).font(LumisTypography.titleMedium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(LumisColors.textPrimary)
            .background(LumisColors.surface, in: LumisRadius.rect(LumisRadius.lg))
        }
        .buttonStyle(.lumisPress)
        .lumisGlass(in: LumisRadius.rect(LumisRadius.lg), interactive: true)
        .accessibilityLabel(title)
    }
}

extension LumisSecondaryButton where Leading == EmptyView {
    init(title: String, action: @escaping () -> Void) {
        self.init(title: title, leading: { EmptyView() }, action: action)
    }
}

/// The Lumis brand mark (the comet from image.svg), template-rendered so it
/// takes the theme's ink color in both light and dark mode.
struct LumisLogoMark: View {
    var size: CGFloat = 120
    var body: some View {
        Image("LumisMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(LumisColors.textPrimary)
            .accessibilityHidden(true)
    }
}

/// The lowercase "lumis" wordmark.
struct LumisWordmark: View {
    var size: CGFloat = 28
    var body: some View {
        Text("lumis")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LumisColors.textPrimary)
            .accessibilityLabel("Lumis")
    }
}

/// Inline Google "G" logo drawn with brand colors (no asset / SDK needed).
struct GoogleLogo: View {
    var size: CGFloat = 18
    var body: some View {
        Text("G")
            .font(.system(size: size, weight: .bold, design: .default))
            .foregroundStyle(
                // Google's official brand colors — a third-party logo, so these
                // intentionally live outside the LumisColors app palette.
                LinearGradient(
                    colors: [Color(hex: "#4285F4"), Color(hex: "#EA4335"),
                             Color(hex: "#FBBC05"), Color(hex: "#34A853")],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .accessibilityHidden(true)
    }
}
