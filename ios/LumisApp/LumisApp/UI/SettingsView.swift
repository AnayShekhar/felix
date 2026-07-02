import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var lumisVM: LumisViewModel

    /// When presented as the full-screen sheet from the sidebar, this provides
    /// the leading "X" that returns to the sidebar.
    var onClose: (() -> Void)?

    // Persisted preferences (only ones wired to real behavior).
    @AppStorage("lumis.pref.wakeWord") private var wakeWord = true

    @State private var showSignOut = false
    @State private var route: SettingsRoute?

    @StateObject private var servicesVM = ConnectedServicesViewModel()
    @State private var showExtensionInstructions = false
    /// Per-service cookie-sync check result, keyed by service id.
    @State private var verifyMessages: [String: String] = [:]
    @State private var verifyingID: String?

    enum SettingsRoute: Hashable { case changeEmail, changePassword, deleteAccount, editProfile }

    var body: some View {
        NavigationStack {
            ZStack {
                LumisColors.parchment.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        profileCard
                        connectedServicesSection
                        voiceSection
                        MemorySection()
                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .refreshable { await servicesVM.fetchStatus() }
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
                case .changeEmail:     ChangeEmailSheet()
                case .changePassword:  ChangePasswordSheet()
                case .deleteAccount:   DeleteAccountView()
                case .editProfile:     EditProfileView()
                }
            }
            .sheet(isPresented: $showExtensionInstructions) {
                ExtensionInstructionsView()
            }
            .task { await servicesVM.fetchStatus() }
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

    // MARK: - Connected services (Chrome extension)

    @ViewBuilder
    private var connectedServicesSection: some View {
        SettingsSection("Connected Services") {
            if servicesVM.hasAnyConnection {
                ForEach(SUPPORTED_SERVICES) { service in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: service.icon)
                                .foregroundColor(LumisColors.carbonBlack.opacity(0.6))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.displayName)
                                    .font(LumisTypography.bodyMedium)
                                    .foregroundColor(LumisColors.carbonBlack)
                                Text(service.description)
                                    .font(LumisTypography.caption)
                                    .foregroundColor(LumisColors.carbonBlack.opacity(0.5))
                            }
                            Spacer()
                            if servicesVM.isConnected(service.id) {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(LumisTypography.caption)
                                    .foregroundColor(LumisColors.success)
                            } else {
                                Text("Not connected")
                                    .font(LumisTypography.caption)
                                    .foregroundColor(LumisColors.carbonBlack.opacity(0.3))
                            }
                        }
                        if servicesVM.isConnected(service.id) {
                            HStack(spacing: 8) {
                                Button(verifyingID == service.id ? "Checking…" : "Verify") {
                                    Task { await verify(service.id) }
                                }
                                .font(LumisTypography.caption)
                                .foregroundColor(LumisColors.carbonBlack.opacity(0.45))
                                .disabled(verifyingID == service.id)
                                if let msg = verifyMessages[service.id] {
                                    Text(msg)
                                        .font(LumisTypography.caption)
                                        .foregroundColor(LumisColors.carbonBlack.opacity(0.45))
                                }
                            }
                            .padding(.leading, 28)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()

                Button(action: { showExtensionInstructions = true }) {
                    Label("Connect more accounts", systemImage: "plus.circle")
                        .font(LumisTypography.bodyMedium)
                        .foregroundColor(LumisColors.powderBlue)
                }
                .padding(.top, 4)
            } else {
                ConnectServicesEmptyState(onGetStarted: { showExtensionInstructions = true })
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

    // MARK: - Cookie-sync verification

    /// Ask the backend whether the Browserbase context actually has cookies for
    /// this service, so the user can confirm the extension sync really worked.
    private func verify(_ serviceID: String) async {
        verifyingID = serviceID
        defer { verifyingID = nil }
        do {
            let result = try await LumisAPI.request(
                "/connect/verify/\(serviceID)",
                token: KeychainManager.token,
                as: VerifyResponse.self
            )
            verifyMessages[serviceID] = result.likelySynced
                ? "✓ \(result.cookieCount) cookies found — should work"
                : "⚠ No cookies — try reconnecting in the extension"
        } catch {
            verifyMessages[serviceID] = "Couldn't check right now"
        }
    }
}

/// Response of `GET /connect/verify/{service}` — cookie NAMES only, never values.
struct VerifyResponse: Codable {
    let service: String
    let domain: String
    let cookieCount: Int
    let cookieNames: [String]
    let likelySynced: Bool

    enum CodingKeys: String, CodingKey {
        case service, domain
        case cookieCount = "cookie_count"
        case cookieNames = "cookie_names"
        case likelySynced = "likely_synced"
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
