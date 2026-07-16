import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var path: [AuthFlowView.AuthRoute]

    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool { email.contains("@") && password.count >= 6 }

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: LumisSpacing.xl) {
                    Text("Welcome back")
                        .font(LumisTypography.displayLarge)
                        .foregroundStyle(LumisColors.textPrimary)
                        .padding(.top, LumisSpacing.xl)
                    Text("Sign in to keep Lumis close at hand.")
                        .font(LumisTypography.bodyMedium)
                        .foregroundStyle(LumisColors.textSecondary)
                        .padding(.top, -LumisSpacing.md)

                    FloatingLabelField(title: "Email address", text: $email,
                                       keyboard: .emailAddress, contentType: .emailAddress)
                    FloatingLabelField(title: "Password", text: $password,
                                       isSecure: true, contentType: .password,
                                       submitLabel: .go, onSubmit: submit)

                    Button("Forgot password?") { path.append(.forgot) }
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.tintStrong)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    LumisPrimaryButton(title: "Sign in",
                                       loading: authVM.isLoading,
                                       enabled: canSubmit, action: submit)
                        .padding(.top, 4)

                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundStyle(LumisColors.textSecondary)
                        Button("Sign up") { path = [.signUp] }
                            .foregroundStyle(LumisColors.textPrimary)
                            .fontWeight(.semibold)
                    }
                    .font(LumisTypography.bodySmall)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, LumisSpacing.xl)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await authVM.login(email: email, password: password) }
    }
}
