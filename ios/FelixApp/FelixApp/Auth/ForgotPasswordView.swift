import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var sent = false
    @State private var checkmark = false

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
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
        VStack(alignment: .leading, spacing: FelixSpacing.xl) {
            Text("Reset your password")
                .font(FelixTypography.displayLarge)
                .foregroundStyle(FelixColors.textPrimary)
                .padding(.top, FelixSpacing.xl)
            Text("Enter your email and we'll send you a reset link.")
                .font(FelixTypography.bodyMedium)
                .foregroundStyle(FelixColors.textSecondary)

            FloatingLabelField(title: "Email address", text: $email,
                               keyboard: .emailAddress, contentType: .emailAddress,
                               submitLabel: .go, onSubmit: send)

            FelixPrimaryButton(title: "Send reset link",
                               loading: authVM.isLoading,
                               enabled: email.contains("@"), action: send)
                .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, FelixSpacing.xl)
    }

    private var successState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(FelixColors.tintSoft).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(FelixColors.tintStrong)
                    .scaleEffect(checkmark ? 1 : 0.3)
                    .opacity(checkmark ? 1 : 0)
            }
            Text("Check your email")
                .font(FelixTypography.titleMedium)
                .foregroundStyle(FelixColors.textPrimary)
            Text("We sent a reset link to \(email).")
                .font(FelixTypography.bodyMedium)
                .foregroundStyle(FelixColors.textSecondary)
                .multilineTextAlignment(.center)
            FelixPrimaryButton(title: "Back to sign in") { dismiss() }
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
