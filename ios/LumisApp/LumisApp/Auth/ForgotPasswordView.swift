import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: LumisSpacing.xl) {
                Text("Reset your password")
                    .font(LumisTypography.displayLarge)
                    .foregroundStyle(LumisColors.textPrimary)
                    .padding(.top, LumisSpacing.xl)
                Text("Password reset by email isn't available yet. Sign in with Apple or Google, or create a new email account.")
                    .font(LumisTypography.bodyMedium)
                    .foregroundStyle(LumisColors.textSecondary)

                FloatingLabelField(title: "Email address", text: $email,
                                   keyboard: .emailAddress, contentType: .emailAddress)

                if let error = authVM.error, !error.isEmpty {
                    Text(error)
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.danger)
                }

                LumisPrimaryButton(title: "Back to sign in",
                                   loading: false,
                                   enabled: true) { dismiss() }
                    .padding(.top, 4)
                Spacer()
            }
            .padding(.horizontal, LumisSpacing.xl)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { authVM.error = nil }
    }
}
