import SwiftUI

// MARK: - Mac detail

struct MacDetailView: View {
    @EnvironmentObject private var macVM: MacConnectionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnlink = false

    var body: some View {
        ZStack {
            LumisColors.parchment.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    SettingsSection("Mac") {
                        infoRow("Name", macVM.macName ?? "Mac")
                        Divider().overlay(LumisColors.divider)
                        infoRow("Status", macVM.connectionState == .linkedOnline ? "Online" : "Offline")
                        if let linked = macVM.linkedAt {
                            Divider().overlay(LumisColors.divider)
                            infoRow("Linked since", linked.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let seen = macVM.lastSeen {
                            Divider().overlay(LumisColors.divider)
                            infoRow("Last active", RelativeTime.friendly(seen.timeIntervalSince1970))
                        }
                    }
                    Button(role: .destructive) { confirmUnlink = true } label: {
                        Text("Unlink Mac")
                            .font(LumisTypography.titleMedium)
                            .foregroundStyle(LumisColors.destructive)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LumisColors.destructive, lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Mac")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Unlink this Mac?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            Button("Unlink", role: .destructive) {
                Task { await macVM.unpair(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.carbonBlack)
            Spacer()
            Text(value).font(LumisTypography.bodyMedium).foregroundStyle(LumisColors.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

// MARK: - Change email

struct ChangeEmailSheet: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""

    var body: some View {
        FormScaffold(title: "Change email") {
            Text("Current: \(authVM.currentUser?.email ?? "")")
                .font(LumisTypography.bodySmall).foregroundStyle(LumisColors.textSecondary)
            FloatingLabelField(title: "New email", text: $newEmail, keyboard: .emailAddress, contentType: .emailAddress)
            FloatingLabelField(title: "Confirm password", text: $password, isSecure: true)
            LumisPrimaryButton(title: "Update", loading: authVM.isLoading,
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
            LumisPrimaryButton(title: "Update", loading: authVM.isLoading,
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
            LumisColors.parchment.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("Delete account")
                    .font(LumisTypography.titleLarge).foregroundStyle(LumisColors.carbonBlack)
                Text("This permanently deletes your Lumis account and unlinks your Mac. This can't be undone. Type DELETE to confirm.")
                    .font(LumisTypography.bodyMedium).foregroundStyle(LumisColors.textSecondary)
                FloatingLabelField(title: "Type DELETE", text: $confirmation)
                Spacer()
                Button { Task { await authVM.deleteAccount() } } label: {
                    Text("Delete my account")
                        .font(LumisTypography.titleMedium).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(confirmation == "DELETE" ? LumisColors.destructive : LumisColors.destructive.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
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
            LumisColors.parchment.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(LumisColors.powderBlue).frame(width: 72, height: 72)
                    Text(authVM.currentUser?.initials ?? "?")
                        .font(LumisTypography.titleLarge).foregroundStyle(LumisColors.carbonBlack)
                }
                FloatingLabelField(title: "Display name", text: $name)
                LumisPrimaryButton(title: "Save") {
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
                LumisColors.parchment.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content()
                    }
                    .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
