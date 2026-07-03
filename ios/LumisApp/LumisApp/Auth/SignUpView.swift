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
            LumisColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Create your account")
                        .font(LumisTypography.titleLarge)
                        .foregroundStyle(LumisColors.textPrimary)
                        .padding(.top, 8)

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
                            .font(LumisTypography.caption)
                            .foregroundStyle(LumisColors.destructive)
                    }

                    LumisPrimaryButton(title: "Create account",
                                       loading: authVM.isLoading,
                                       enabled: canSubmit, action: submit)
                        .padding(.top, 4)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundStyle(LumisColors.textSecondary)
                        Button("Sign in") { path = [.signIn] }
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
        Task { await authVM.register(name: name, email: email, password: password) }
    }
}
