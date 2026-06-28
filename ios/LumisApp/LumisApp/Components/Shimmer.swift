import SwiftUI

/// Skeleton shimmer: a highlight sweep left→right over placeholder content.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.screen)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

/// Full-screen working overlay: blurred material + small Lumis shape + label.
struct WorkingOverlay: View {
    var label: String = "Working on it…"
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                LumisShapeView(state: .thinking, containerSize: 80)
                Text(label)
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.textSecondary)
            }
        }
        .accessibilityLabel(label)
    }
}
