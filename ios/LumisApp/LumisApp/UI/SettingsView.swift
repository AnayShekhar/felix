import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var macVM: MacConnectionViewModel
    @EnvironmentObject private var lumisVM: LumisViewModel

    /// When presented as the full-screen sheet from the sidebar, this provides
    /// the leading "X" that returns to the sidebar.
    var onClose: (() -> Void)?

    // Persisted preferences (only ones wired to real behavior).
    @AppStorage("lumis.pref.wakeWord") private var wakeWord = true

    @State private var showCodeEntry = false
    @State private var showSignOut = false
    @State private var route: SettingsRoute?

    enum SettingsRoute: Hashable { case macDetail, changeEmail, changePassword, deleteAccount, editProfile }

    var body: some View {
        NavigationStack {
            ZStack {
                LumisColors.parchment.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        profileCard
                        macSection
                        voiceSection
                        MemorySection()
                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onClose() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LumisColors.carbonBlack)
                        }
                        .accessibilityLabel("Close settings")
                    }
                }
            }
            .navigationDestination(item: $route) { dest in
                switch dest {
                case .macDetail:       MacDetailView()
                case .changeEmail:     ChangeEmailSheet()
                case .changePassword:  ChangePasswordSheet()
                case .deleteAccount:   DeleteAccountView()
                case .editProfile:     EditProfileView()
                }
            }
            .sheet(isPresented: $showCodeEntry) {
                MacCodeEntryView().environmentObject(macVM)
            }
            .confirmationDialog("Sign out of Lumis?", isPresented: $showSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { authVM.logout() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        Button { route = .editProfile } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LumisColors.powderBlue).frame(width: 52, height: 52)
                    Text(authVM.currentUser?.initials ?? "?")
                        .font(LumisTypography.titleMedium)
                        .foregroundStyle(LumisColors.carbonBlack)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(authVM.currentUser?.displayName ?? "Your account")
                        .font(LumisTypography.titleMedium)
                        .foregroundStyle(LumisColors.carbonBlack)
                    Text(authVM.currentUser?.email ?? "")
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(LumisColors.textTertiary)
            }
            .padding(16)
            .background(LumisColors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LumisColors.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mac

    private var macSection: some View {
        SettingsSection("Mac Connection") {
            switch macVM.connectionState {
            case .unlinked, .linking:
                SettingsRow(icon: "laptopcomputer", title: "Connect your Mac") {
                    Button("Connect") { showCodeEntry = true }
                        .font(LumisTypography.captionMedium)
                        .foregroundStyle(LumisColors.carbonBlack)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(LumisColors.powderBlue, in: Capsule())
                }
            case .linkedOnline, .linkedOffline:
                Button { route = .macDetail } label: {
                    SettingsRow(icon: "laptopcomputer", title: macVM.macName ?? "Mac") {
                        HStack(spacing: 6) {
                            Circle().fill(macVM.connectionState == .linkedOnline ? LumisColors.success : LumisColors.amber)
                                .frame(width: 8, height: 8)
                            Text(macVM.connectionState == .linkedOnline ? "Connected" : "Offline")
                                .font(LumisTypography.bodySmall)
                                .foregroundStyle(macVM.connectionState == .linkedOnline ? LumisColors.powderBlue : LumisColors.amber)
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(LumisColors.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        SettingsSection("Voice") {
            Toggle(isOn: $wakeWord) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hey Lumis").font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.carbonBlack)
                    Text("Listen for your wake word in the background")
                        .font(LumisTypography.caption).foregroundStyle(LumisColors.textSecondary)
                }
            }
            .tint(LumisColors.powderBlue)
            .settingsRowPadding()
            .onChange(of: wakeWord) { _, on in lumisVM.setWakeWord(on) }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection("Account") {
            navRow("Change email") { route = .changeEmail }
            navRow("Change password") { route = .changePassword }
            Button { showSignOut = true } label: {
                SettingsRow(icon: nil, title: "Sign out") { EmptyView() }
            }.buttonStyle(.plain)
            Button { route = .deleteAccount } label: {
                HStack {
                    Text("Delete account").font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.destructive)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(LumisColors.textTertiary)
                }.settingsRowPadding()
            }.buttonStyle(.plain)
        }
    }

    // MARK: - About

    @State private var safariURL: URL?
    @State private var showFeedback = false

    private var aboutSection: some View {
        SettingsSection("About") {
            HStack {
                Text("Version").font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.carbonBlack)
                Spacer()
                Text("Version \(LumisConfig.appVersion) (\(LumisConfig.buildNumber))")
                    .font(LumisTypography.bodyMedium).foregroundStyle(LumisColors.textSecondary)
            }.settingsRowPadding()
            navRow("Privacy Policy") { safariURL = URL(string: LumisConfig.privacyPolicyURL) }
            navRow("Terms of Service") { safariURL = URL(string: LumisConfig.termsURL) }
            navRow("Send feedback") { showFeedback = true }
        }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
        .sheet(isPresented: $showFeedback) {
            if MailView.canSend {
                MailView(recipient: LumisConfig.supportEmail, subject: "Lumis Feedback")
            } else {
                Text("No mail account is set up on this device.")
                    .font(LumisTypography.bodyMedium).padding()
            }
        }
    }

    private func navRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(icon: nil, title: title) {
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(LumisColors.textTertiary)
            }
        }.buttonStyle(.plain)
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
