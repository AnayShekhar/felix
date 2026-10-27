import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var path: [AuthFlowView.AuthRoute]

    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool { email.contains("@") && password.count >= 6 }

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: FelixSpacing.xl) {
                    Text("Welcome back")
                        .font(FelixTypography.displayLarge)
                        .foregroundStyle(FelixColors.textPrimary)
                        .padding(.top, FelixSpacing.xl)
                    Text("Sign in to keep Felix close at hand.")
                        .font(FelixTypography.bodyMedium)
                        .foregroundStyle(FelixColors.textSecondary)
                        .padding(.top, -FelixSpacing.md)

                    FloatingLabelField(title: "Email address", text: $email,
                                       keyboard: .emailAddress, contentType: .emailAddress)
                    FloatingLabelField(title: "Password", text: $password,
                                       isSecure: true, contentType: .password,
                                       submitLabel: .go, onSubmit: submit)

                    Button("Forgot password?") { path.append(.forgot) }
                        .font(FelixTypography.bodySmall)
                        .foregroundStyle(FelixColors.tintStrong)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    FelixPrimaryButton(title: "Sign in",
                                       loading: authVM.isLoading,
                                       enabled: canSubmit, action: submit)
                        .padding(.top, 4)

                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundStyle(FelixColors.textSecondary)
                        Button("Sign up") { path = [.signUp] }
                            .foregroundStyle(FelixColors.textPrimary)
                            .fontWeight(.semibold)
                    }
                    .font(FelixTypography.bodySmall)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, FelixSpacing.xl)
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
