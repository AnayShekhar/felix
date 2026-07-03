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
                VStack(alignment: .leading, spacing: 22) {
                    Text("Welcome back")
                        .font(LumisTypography.titleLarge)
                        .foregroundStyle(LumisColors.textPrimary)
                        .padding(.top, 8)

                    FloatingLabelField(title: "Email address", text: $email,
                                       keyboard: .emailAddress, contentType: .emailAddress)
                    FloatingLabelField(title: "Password", text: $password,
                                       isSecure: true, contentType: .password,
                                       submitLabel: .go, onSubmit: submit)

                    Button("Forgot password?") { path.append(.forgot) }
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.tint)
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
                .padding(.horizontal, 24)
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
