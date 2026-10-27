import SwiftUI

/// Launch screen: a quiet instance of Felix's living mark while the stored
/// session is validated. It is deliberately an arrival moment, not a branded
/// loading billboard.
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
            VStack(spacing: FelixSpacing.lg) {
                ScribbleView(state: .idle, containerSize: 128)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
                FelixWordmark(size: 24)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Felix is starting")
    }
}

#Preview { SplashView() }
