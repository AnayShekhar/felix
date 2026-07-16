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
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: LumisSpacing.xs) {
                            LumisLogoMark(size: 24)
                            LumisWordmark(size: 22)
                        }
                        .padding(.top, LumisSpacing.lg)

                        Spacer(minLength: LumisSpacing.xxl)

                        VStack(alignment: .leading, spacing: LumisSpacing.md) {
                            ScribbleView(state: .idle, containerSize: 150)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, LumisSpacing.xs)

                            Text("Your world,\nhandled.")
                                .font(LumisTypography.displayLarge)
                                .foregroundStyle(LumisColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Say what you need. Lumis works across the accounts you choose to connect.")
                                .font(LumisTypography.bodyLarge)
                                .foregroundStyle(LumisColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: LumisSpacing.xxl)

                        VStack(spacing: LumisSpacing.md) {
                            LumisPrimaryButton(title: "Continue with email") {
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

                        HStack(spacing: LumisSpacing.xs) {
                            Text("Already have an account?")
                                .foregroundStyle(LumisColors.textSecondary)
                            Button("Sign in") { path.append(.signIn) }
                                .foregroundStyle(LumisColors.tintStrong)
                        }
                        .font(LumisTypography.bodySmall)
                        .frame(maxWidth: .infinity)
                        .padding(.top, LumisSpacing.lg)

                        legal.padding(.top, LumisSpacing.lg)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, LumisSpacing.xl)
                    .padding(.bottom, LumisSpacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var legal: some View {
        Text("By continuing you agree to our [Terms](\(LumisConfig.termsURL)) and [Privacy Policy](\(LumisConfig.privacyPolicyURL)).")
            .font(LumisTypography.caption)
            .foregroundStyle(LumisColors.textTertiary)
            .tint(LumisColors.tintStrong)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in openURL(url); return .handled })
    }
}

#Preview {
    AuthFlowView().environmentObject(AuthViewModel())
}
