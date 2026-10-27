import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var path: [AuthFlowView.AuthRoute]

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""

    private var strength: PasswordStrength { .evaluate(password) }
    private var canSubmit: Bool {
        !name.isEmpty && email.contains("@") && password.count >= 6 && password == confirm
    }

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: FelixSpacing.xl) {
                    Text("Create your account")
                        .font(FelixTypography.displayLarge)
                        .foregroundStyle(FelixColors.textPrimary)
                        .padding(.top, FelixSpacing.xl)
                    Text("A private place for the things you ask Felix to do.")
                        .font(FelixTypography.bodyMedium)
                        .foregroundStyle(FelixColors.textSecondary)
                        .padding(.top, -FelixSpacing.md)

                    FloatingLabelField(title: "Full name", text: $name,
                                       contentType: .name)
                    FloatingLabelField(title: "Email address", text: $email,
                                       keyboard: .emailAddress, contentType: .emailAddress)
                    VStack(alignment: .leading, spacing: 14) {
                        FloatingLabelField(title: "Password", text: $password,
                                           isSecure: true, contentType: .newPassword)
                        PasswordStrengthBar(strength: strength)
                            .padding(.bottom, strength == .empty ? 0 : 14)
                    }
                    FloatingLabelField(title: "Confirm password", text: $confirm,
                                       isSecure: true, submitLabel: .go,
                                       onSubmit: submit)
                    if !confirm.isEmpty && confirm != password {
                        Text("Passwords don't match.")
                            .font(FelixTypography.caption)
                            .foregroundStyle(FelixColors.destructive)
                    }

                    FelixPrimaryButton(title: "Create account",
                                       loading: authVM.isLoading,
                                       enabled: canSubmit, action: submit)
                        .padding(.top, 4)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundStyle(FelixColors.textSecondary)
                        Button("Sign in") { path = [.signIn] }
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
        Task { await authVM.register(name: name, email: email, password: password) }
    }
}
