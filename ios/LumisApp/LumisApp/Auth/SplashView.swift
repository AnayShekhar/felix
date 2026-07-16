import SwiftUI

/// Launch screen: a quiet instance of Lumis's living mark while the stored
/// session is validated. It is deliberately an arrival moment, not a branded
/// loading billboard.
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(spacing: LumisSpacing.lg) {
                ScribbleView(state: .idle, containerSize: 128)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
                LumisWordmark(size: 24)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lumis is starting")
    }
}

#Preview { SplashView() }
