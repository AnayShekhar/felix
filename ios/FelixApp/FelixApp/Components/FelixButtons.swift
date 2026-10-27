import SwiftUI

/// Full-width filled button: the app's one confident, high-contrast action.
struct FelixPrimaryButton: View {
    let title: String
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled && !loading { action() } }) {
            ZStack {
                if loading {
                    ProgressView().tint(FelixColors.background)
                } else {
                    Text(title).font(FelixTypography.titleMedium)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(FelixColors.textPrimary)
            .foregroundStyle(FelixColors.background)
            .clipShape(FelixRadius.rect(FelixRadius.lg))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.felixPress)
        .disabled(!enabled || loading)
        .accessibilityLabel(title)
    }
}

/// Full-width outlined button: Carbon Black border + text, optional leading icon.
struct FelixSecondaryButton<Leading: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading()
                Text(title).font(FelixTypography.titleMedium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(FelixColors.textPrimary)
            .background(FelixColors.surface, in: FelixRadius.rect(FelixRadius.lg))
        }
        .buttonStyle(.felixPress)
        .felixGlass(in: FelixRadius.rect(FelixRadius.lg), interactive: true)
        .accessibilityLabel(title)
    }
}

extension FelixSecondaryButton where Leading == EmptyView {
    init(title: String, action: @escaping () -> Void) {
        self.init(title: title, leading: { EmptyView() }, action: action)
    }
}

/// The Felix brand mark (the comet from image.svg), template-rendered so it
/// takes the theme's ink color in both light and dark mode.
struct FelixLogoMark: View {
    var size: CGFloat = 120
    var body: some View {
        Image("FelixMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(FelixColors.textPrimary)
            .accessibilityHidden(true)
    }
}

/// The lowercase "felix" wordmark.
struct FelixWordmark: View {
    var size: CGFloat = 28
    var body: some View {
        Text("felix")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(FelixColors.textPrimary)
            .accessibilityLabel("Felix")
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
                // intentionally live outside the FelixColors app palette.
                LinearGradient(
                    colors: [Color(hex: "#4285F4"), Color(hex: "#EA4335"),
                             Color(hex: "#FBBC05"), Color(hex: "#34A853")],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .accessibilityHidden(true)
    }
}
