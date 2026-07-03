import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var sent = false
    @State private var checkmark = false

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            if sent {
                successState
            } else {
                formState
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formState: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Reset your password")
                .font(LumisTypography.titleLarge)
                .foregroundStyle(LumisColors.textPrimary)
                .padding(.top, 8)
            Text("Enter your email and we'll send you a reset link.")
                .font(LumisTypography.bodyMedium)
                .foregroundStyle(LumisColors.textSecondary)

            FloatingLabelField(title: "Email address", text: $email,
                               keyboard: .emailAddress, contentType: .emailAddress,
                               submitLabel: .go, onSubmit: send)

            LumisPrimaryButton(title: "Send reset link",
                               loading: authVM.isLoading,
                               enabled: email.contains("@"), action: send)
                .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var successState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(LumisColors.tintSoft).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LumisColors.success)
                    .scaleEffect(checkmark ? 1 : 0.3)
                    .opacity(checkmark ? 1 : 0)
            }
            Text("Check your email")
                .font(LumisTypography.titleMedium)
                .foregroundStyle(LumisColors.textPrimary)
            Text("We sent a reset link to \(email).")
                .font(LumisTypography.bodyMedium)
                .foregroundStyle(LumisColors.textSecondary)
                .multilineTextAlignment(.center)
            LumisPrimaryButton(title: "Back to sign in") { dismiss() }
                .padding(.top, 8)
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { checkmark = true }
        }
    }

    private func send() {
        Task {
            if await authVM.sendPasswordReset(email: email) {
                withAnimation(.easeInOut) { sent = true }
            }
        }
    }
}
