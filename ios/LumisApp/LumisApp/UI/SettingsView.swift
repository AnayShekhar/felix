import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var lumisVM: LumisViewModel

    /// When presented as the full-screen sheet from the sidebar, this provides
    /// the leading "X" that returns to the sidebar.
    var onClose: (() -> Void)?

    // Persisted preferences (only ones wired to real behavior).
    @AppStorage("lumis.pref.wakeWord") private var wakeWord = true
    @AppStorage(LumisAppearance.storageKey) private var appearanceRaw = LumisAppearance.system.rawValue

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
                LumisColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: LumisSpacing.xl) {
                        profileCard
                        connectedServicesSection
                        appearanceSection
                        voiceSection
                        MemorySection()
                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, LumisSpacing.screenMargin)
                    .padding(.top, LumisSpacing.sm)
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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LumisColors.textPrimary)
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
                    Circle().fill(LumisColors.tint).frame(width: 52, height: 52)
                    Text(authVM.currentUser?.initials ?? "?")
                        .font(LumisTypography.bodyLargeEmphasized)
                        .foregroundStyle(LumisColors.onTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // Medium, not semibold — the "Settings" large title is this
                    // screen's one dominant heading.
                    Text(authVM.currentUser?.displayName ?? "Your account")
                        .font(LumisTypography.bodyLargeEmphasized)
                        .foregroundStyle(LumisColors.textPrimary)
                    Text(authVM.currentUser?.email ?? "")
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LumisColors.textTertiary)
            }
            .padding(LumisSpacing.lg)
            // Material card, continuous corners, no drawn border — depth
            // through blur and a near-invisible shadow.
            .background(.ultraThinMaterial, in: LumisRadius.rect(LumisRadius.card))
            .shadow(color: LumisColors.shadow, radius: 8, y: 4)
        }
        .buttonStyle(.lumisPress)
    }

    // MARK: - Connected services (Chrome extension)

    @ViewBuilder
    private var connectedServicesSection: some View {
        SettingsSection("Connected Services") {
            // Connection status lives exclusively here — never on the main screen.
            serverStatusRow
            Divider().overlay(LumisColors.divider)
            ExtensionSyncBanner(state: servicesVM.syncState)
            Divider().overlay(LumisColors.divider)
            if servicesVM.hasAnyConnection {
                ForEach(SUPPORTED_SERVICES) { service in
                    VStack(alignment: .leading, spacing: LumisSpacing.sm) {
                        HStack(spacing: LumisSpacing.md) {
                            Image(systemName: service.icon)
                                .font(.body.weight(.medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(LumisColors.textSecondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.displayName)
                                    .font(LumisTypography.bodyMedium)
                                    .foregroundColor(LumisColors.textPrimary)
                                Text(service.description)
                                    .font(LumisTypography.caption)
                                    .foregroundColor(LumisColors.textSecondary)
                            }
                            Spacer()
                            if servicesVM.isConnected(service.id) {
                                Label("Connected", systemImage: "checkmark.circle")
                                    .font(LumisTypography.captionMedium)
                                    .foregroundColor(LumisColors.tintStrong)
                            } else {
                                Text("Not connected")
                                    .font(LumisTypography.caption)
                                    .foregroundColor(LumisColors.textTertiary)
                            }
                        }
                        if servicesVM.isConnected(service.id) {
                            HStack(spacing: LumisSpacing.sm) {
                                Button(verifyingID == service.id ? "Checking…" : "Verify") {
                                    Task { await verify(service.id) }
                                }
                                .font(LumisTypography.captionMedium)
                                .foregroundColor(LumisColors.textSecondary)
                                .disabled(verifyingID == service.id)
                                if let msg = verifyMessages[service.id] {
                                    Text(msg)
                                        .font(LumisTypography.caption)
                                        .foregroundColor(LumisColors.textTertiary)
                                }
                            }
                            // Aligns with the text column (28pt icon + 12pt gap).
                            .padding(.leading, 40)
                        }
                    }
                    .padding(.vertical, LumisSpacing.md)
                }

                Divider().overlay(LumisColors.divider)

                Button(action: { showExtensionInstructions = true }) {
                    Label("Connect more accounts", systemImage: "plus.circle")
                        .font(LumisTypography.bodyMedium)
                        .foregroundColor(LumisColors.tintStrong)
                }
                .padding(.top, LumisSpacing.sm)
            } else {
                ConnectServicesEmptyState(onGetStarted: { showExtensionInstructions = true })
            }
        }
    }

    /// Live link between this phone and the Lumis backend, stated plainly.
    private var serverStatusRow: some View {
        ServerStatusRow(ws: lumisVM.ws)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            VStack(alignment: .leading, spacing: LumisSpacing.sm) {
                Text("Theme")
                    .font(LumisTypography.bodyLarge)
                    .foregroundStyle(LumisColors.textPrimary)
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(LumisAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .settingsRowPadding()
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        SettingsSection("Voice") {
            Toggle(isOn: $wakeWord) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hey Lumis").font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.textPrimary)
                    Text("Listen for your wake word in the background")
                        .font(LumisTypography.caption).foregroundStyle(LumisColors.textSecondary)
                }
            }
            .tint(LumisColors.tint)
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
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LumisColors.textTertiary)
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
                Text("Version").font(LumisTypography.bodyLarge).foregroundStyle(LumisColors.textPrimary)
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
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LumisColors.textTertiary)
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


/// The phone ↔ backend link, observed directly so the row updates live.
private struct ServerStatusRow: View {
    @ObservedObject var ws: WebSocketClient

    var body: some View {
        HStack(spacing: LumisSpacing.md) {
            Image(systemName: ws.connected ? "checkmark.circle" : "circle.dashed")
                .font(.title3.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ws.connected ? LumisColors.tintStrong : LumisColors.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.connected ? "Connected to Lumis" : "Connecting to Lumis…")
                    .font(LumisTypography.titleSmall)
                    .foregroundStyle(LumisColors.textPrimary)
                Text(ws.connected
                     ? "This phone is receiving live updates."
                     : "Trying to reach the Lumis server.")
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .settingsRowPadding()
        .accessibilityElement(children: .combine)
    }
}

/// The honest phone ↔ extension link status shown at the top of Connected
/// Services (never / recently synced / stale). Same wording as the extension.
struct ExtensionSyncBanner: View {
    let state: ExtensionSyncState

    var body: some View {
        HStack(spacing: LumisSpacing.md) {
            Image(systemName: state.icon)
                .font(.title3.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(LumisTypography.titleSmall)
                    .foregroundStyle(LumisColors.textPrimary)
                Text(state.detail)
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .settingsRowPadding()
        .accessibilityElement(children: .combine)
    }
}
