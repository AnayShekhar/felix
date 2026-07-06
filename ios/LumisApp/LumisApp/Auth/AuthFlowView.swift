import AuthenticationServices
import SwiftUI

/// Root of the unauthenticated experience. Welcome screen + navigation to the
/// email sign-in / sign-up / forgot-password screens.
struct AuthFlowView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var path: [AuthRoute] = []

    enum AuthRoute: Hashable { case signIn, signUp, forgot }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signIn: SignInView(path: $path)
                    case .signUp: SignUpView(path: $path)
                    case .forgot: ForgotPasswordView()
                    }
                }
        }
        .tint(LumisColors.textPrimary)
        .overlay(alignment: .bottom) {
            if let error = authVM.error {
                ErrorToast(message: error) { authVM.error = nil }
                    .padding(.bottom, 24)
            }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var path: [AuthFlowView.AuthRoute]
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                LumisLogoMark(size: 110)
                LumisWordmark(size: 28).padding(.top, 20)
                Text("Your world, automated.")
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.textSecondary)
                    .padding(.top, 8)
                Spacer()

                VStack(spacing: 12) {
                    LumisSecondaryButton(title: "Continue with email") {
                        path.append(.signUp)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        authVM.handleAppleCompletion(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    // ASAuthorizationAppleIDButton only reads its style at
                    // creation — re-create it when the scheme flips live.
                    .id(colorScheme)
                    .frame(height: 54)
                    .clipShape(LumisRadius.rect(LumisRadius.lg))

                    LumisSecondaryButton(title: "Continue with Google") {
                        GoogleLogo()
                    } action: {
                        Task { await authVM.signInWithGoogle() }
                    }
                }
                .padding(.horizontal, 28)

                legal.padding(.top, 18).padding(.horizontal, 32)
            }
            .padding(.bottom, 28)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var legal: some View {
        Text("By continuing you agree to our [Terms](\(LumisConfig.termsURL)) and [Privacy Policy](\(LumisConfig.privacyPolicyURL)).")
            .font(LumisTypography.caption)
            .foregroundStyle(LumisColors.textTertiary)
            .tint(LumisColors.tint)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in openURL(url); return .handled })
    }
}

#Preview {
    AuthFlowView().environmentObject(AuthViewModel())
}
