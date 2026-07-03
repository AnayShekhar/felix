import SwiftUI

/// Launch screen: animated Lumis shape + wordmark on Parchment. Shown while the
/// app validates a stored token (`AuthViewModel.isLoading`).
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(spacing: 28) {
                LumisShapeView(state: .thinking, containerSize: 180)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
                LumisWordmark(size: 28)
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
