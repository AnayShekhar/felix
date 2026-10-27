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
        .tint(FelixColors.textPrimary)
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
            FelixColors.background.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: FelixSpacing.xs) {
                            FelixLogoMark(size: 24)
                            FelixWordmark(size: 22)
                        }
                        .padding(.top, FelixSpacing.lg)

                        Spacer(minLength: FelixSpacing.xxl)

                        VStack(alignment: .leading, spacing: FelixSpacing.md) {
                            ScribbleView(state: .idle, containerSize: 150)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, FelixSpacing.xs)

                            Text("Your world,\nhandled.")
                                .font(FelixTypography.displayLarge)
                                .foregroundStyle(FelixColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Say what you need. Felix works across the accounts you choose to connect.")
                                .font(FelixTypography.bodyLarge)
                                .foregroundStyle(FelixColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: FelixSpacing.xxl)

                        VStack(spacing: FelixSpacing.md) {
                            FelixPrimaryButton(title: "Continue with email") {
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
                            .clipShape(FelixRadius.rect(FelixRadius.lg))

                            FelixSecondaryButton(title: "Continue with Google") {
                                GoogleLogo()
                            } action: {
                                Task { await authVM.signInWithGoogle() }
                            }
                        }

                        HStack(spacing: FelixSpacing.xs) {
                            Text("Already have an account?")
                                .foregroundStyle(FelixColors.textSecondary)
                            Button("Sign in") { path.append(.signIn) }
                                .foregroundStyle(FelixColors.tintStrong)
                        }
                        .font(FelixTypography.bodySmall)
                        .frame(maxWidth: .infinity)
                        .padding(.top, FelixSpacing.lg)

                        legal.padding(.top, FelixSpacing.lg)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, FelixSpacing.xl)
                    .padding(.bottom, FelixSpacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var legal: some View {
        Text("By continuing you agree to our [Terms](\(FelixConfig.termsURL)) and [Privacy Policy](\(FelixConfig.privacyPolicyURL)).")
            .font(FelixTypography.caption)
            .foregroundStyle(FelixColors.textTertiary)
            .tint(FelixColors.tintStrong)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in openURL(url); return .handled })
    }
}

#Preview {
    AuthFlowView().environmentObject(AuthViewModel())
}
