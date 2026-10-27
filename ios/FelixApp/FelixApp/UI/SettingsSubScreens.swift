import SwiftUI

// MARK: - Change email

struct ChangeEmailSheet: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""

    var body: some View {
        FormScaffold(title: "Change email") {
            Text("Current: \(authVM.currentUser?.email ?? "")")
                .font(FelixTypography.bodySmall).foregroundStyle(FelixColors.textSecondary)
            FloatingLabelField(title: "New email", text: $newEmail, keyboard: .emailAddress, contentType: .emailAddress)
            FloatingLabelField(title: "Confirm password", text: $password, isSecure: true)
            FelixPrimaryButton(title: "Update", loading: authVM.isLoading,
                               enabled: newEmail.contains("@") && password.count >= 6) {
                Task { if await authVM.changeEmail(newEmail: newEmail, password: password) { dismiss() } }
            }
        }
    }
}

// MARK: - Change password

struct ChangePasswordSheet: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""

    private var strength: PasswordStrength { .evaluate(newPassword) }

    var body: some View {
        FormScaffold(title: "Change password") {
            FloatingLabelField(title: "Current password", text: $current, isSecure: true)
            FloatingLabelField(title: "New password", text: $newPassword, isSecure: true)
            PasswordStrengthBar(strength: strength).padding(.bottom, strength == .empty ? 0 : 12)
            FloatingLabelField(title: "Confirm new password", text: $confirm, isSecure: true)
            FelixPrimaryButton(title: "Update", loading: authVM.isLoading,
                               enabled: current.count >= 6 && newPassword.count >= 6 && newPassword == confirm) {
                Task { if await authVM.changePassword(current: current, newPassword: newPassword) { dismiss() } }
            }
        }
    }
}

// MARK: - Delete account

struct DeleteAccountView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var confirmation = ""

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("Delete account")
                    .font(FelixTypography.titleLarge).foregroundStyle(FelixColors.textPrimary)
                Text("This permanently deletes your Felix account and unlinks your Mac. This can't be undone. Type DELETE to confirm.")
                    .font(FelixTypography.bodyMedium).foregroundStyle(FelixColors.textSecondary)
                FloatingLabelField(title: "Type DELETE", text: $confirmation)
                Spacer()
                Button { Task { await authVM.deleteAccount() } } label: {
                    Text("Delete my account")
                        .font(FelixTypography.titleMedium).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(confirmation == "DELETE" ? FelixColors.destructive : FelixColors.destructive.opacity(0.35))
                        .clipShape(FelixRadius.rect(FelixRadius.lg))
                }
                .buttonStyle(.felixPress)
                .disabled(confirmation != "DELETE")
            }
            .padding(24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumis.displayNameOverride") private var nameOverride = ""
    @State private var name = ""

    var body: some View {
        ZStack {
            FelixColors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(FelixColors.tint).frame(width: 72, height: 72)
                    Text(authVM.currentUser?.initials ?? "?")
                        .font(FelixTypography.titleLarge).foregroundStyle(FelixColors.onTint)
                }
                FloatingLabelField(title: "Display name", text: $name)
                FelixPrimaryButton(title: "Save") {
                    nameOverride = name
                    dismiss()
                }
                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = nameOverride.isEmpty ? (authVM.currentUser?.displayName ?? "") : nameOverride }
    }
}

// MARK: - Shared scaffold

private struct FormScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        NavigationStack {
            ZStack {
                FelixColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: FelixSpacing.xl) {
                        content()
                    }
                    .padding(FelixSpacing.xl)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
