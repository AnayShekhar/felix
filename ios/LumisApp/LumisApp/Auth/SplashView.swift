import SwiftUI

/// Launch screen: the Lumis mark + wordmark. Shown while the app validates a
/// stored token (`AuthViewModel.isLoading`).
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(spacing: 28) {
                LumisLogoMark(size: 150)
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
