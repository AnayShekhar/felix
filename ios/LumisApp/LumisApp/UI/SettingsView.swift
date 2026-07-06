import SwiftUI

/// Settings, in the visual language of Apple's own Settings app: plain
/// inset-grouped sections with uniform leading icon chips, hairline inset
/// separators, muted section headers/footers, a consistent 44pt row rhythm,
/// and the accent color reserved for interactive elements (toggles, links,
/// the Connect action). The profile summary at the top is the single
/// stronger visual container on the screen.
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
                                .font(.subheadline.weight(.medium))
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
            // The backend pushes connect_status_changed the moment a cookie
            // sync or Google consent lands — re-query real state right away.
            .onReceive(lumisVM.ws.events) { env in
                if env.event == "connect_status_changed" {
                    Task { await servicesVM.fetchStatus() }
                }
            }
            .confirmationDialog("Sign out of Lumis?", isPresented: $showSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { authVM.logout() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Profile (the one emphasized container)

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
                SettingsChevron()
            }
            .padding(LumisSpacing.lg)
            // Material card, continuous corners, no drawn border — depth
            // through blur and a near-invisible shadow. Deliberately the only
            // card treatment in Settings.
            .background(.ultraThinMaterial, in: LumisRadius.rect(LumisRadius.card))
            .shadow(color: LumisColors.shadow, radius: 8, y: 4)
        }
        .buttonStyle(.lumisPress)
    }

    // MARK: - Connected services (Chrome extension)

    @ViewBuilder
    private var connectedServicesSection: some View {
        SettingsSection(
            "Connected services",
            footer: "Accounts are connected on your computer through the Lumis browser extension. Google API access is granted here."
        ) {
            // Connection status lives exclusively here — never on the main screen.
            ServerStatusRow(ws: lumisVM.ws)
            SettingsDivider(hasIcon: true)
            ExtensionSyncBanner(state: servicesVM.syncState,
                                staleNote: servicesVM.errorMessage)
            SettingsDivider(hasIcon: true)
            // Google OAuth (API access) — what Gmail/Sheets/Calendar tools run
            // on. Separate from the cookie rows: cookies sign the cloud
            // browser in; this grants Lumis the Google APIs themselves.
            googleAPIRow
            if servicesVM.hasAnyConnection {
                SettingsDivider(hasIcon: true)
                ForEach(SUPPORTED_SERVICES) { service in
                    serviceRow(service)
                    if service.id != SUPPORTED_SERVICES.last?.id {
                        SettingsDivider(hasIcon: true)
                    }
                }
                SettingsDivider(hasIcon: true)
                Button {
                    showExtensionInstructions = true
                } label: {
                    SettingsRow(icon: "plus", title: "Connect more accounts") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            } else if servicesVM.syncState == .neverConnected {
                // Only pitch "get started" when the backend *confirmed* nothing
                // is connected — never while checking or unreachable.
                SettingsDivider(hasIcon: true)
                ConnectServicesEmptyState(onGetStarted: { showExtensionInstructions = true })
            }
        }
    }

    /// One connected service: uniform icon chip, name + what it does, an honest
    /// trailing status (with when the cookies last synced, if known), and —
    /// when connected — a small interactive Verify link beneath, aligned to
    /// the text column.
    @ViewBuilder
    private func serviceRow(_ service: ServiceDefinition) -> some View {
        let connected = servicesVM.isConnected(service.id)
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: service.icon,
                        title: service.displayName,
                        subtitle: connected
                            ? (servicesVM.syncCaption(for: service.id) ?? service.description)
                            : service.description) {
                ServiceStatusLabel(connected: connected)
            }
            if connected {
                HStack(spacing: LumisSpacing.sm) {
                    Button(verifyingID == service.id ? "Checking…" : "Verify") {
                        Task { await verify(service.id) }
                    }
                    .font(LumisTypography.captionMedium)
                    .foregroundStyle(LumisColors.tintStrong)
                    .disabled(verifyingID == service.id)
                    if let msg = verifyMessages[service.id] {
                        Text(msg)
                            .font(LumisTypography.caption)
                            .foregroundStyle(LumisColors.textTertiary)
                    }
                }
                // Aligns with the text column (16 margin + 29 chip + 12 gap).
                .padding(.leading, LumisSpacing.lg + 29 + LumisSpacing.md)
                .padding(.bottom, 11)
                .padding(.top, -4)
            }
        }
    }

    // MARK: - Google API access (OAuth consent)

    @State private var googleConnectError: String?

    private var googleAPIRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: "key",
                        title: "Google account",
                        subtitle: "Gmail, Sheets, Calendar, Docs, Drive") {
                if servicesVM.googleAPIConnected {
                    SettingsDetailText("Connected")
                } else {
                    Button("Connect") { connectGoogle() }
                        .font(LumisTypography.bodyMedium)
                        .foregroundStyle(LumisColors.tintStrong)
                }
            }
            if let googleConnectError {
                Text(googleConnectError)
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.destructive)
                    .padding(.leading, LumisSpacing.lg + 29 + LumisSpacing.md)
                    .padding(.bottom, 11)
                    .padding(.top, -4)
            }
        }
    }

    /// Fetch the consent URL and open it in-app; status refreshes when the
    /// Safari sheet is dismissed after the user finishes the Google flow.
    private func connectGoogle() {
        googleConnectError = nil
        Task {
            do {
                safariURL = try await APIClient.googleConnectURL(baseURL: LumisConfig.backendURL)
            } catch {
                googleConnectError = (error as NSError).localizedDescription
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            SettingsRow(icon: "circle.lefthalf.filled", title: "Theme") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(LumisAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(LumisColors.textSecondary)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        SettingsSection(
            "Voice",
            footer: "Saying \u{201C}Hey Lumis\u{201D} is the only way to start a voice request — there is no microphone button."
        ) {
            SettingsRow(icon: "waveform",
                        title: "\u{201C}Hey Lumis\u{201D}",
                        subtitle: "Listen for your wake word in the background") {
                Toggle("", isOn: $wakeWord)
                    .labelsHidden()
                    .tint(LumisColors.tint)
            }
            .onChange(of: wakeWord) { _, on in lumisVM.setWakeWord(on) }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection("Account") {
            navRow("Change email") { route = .changeEmail }
            SettingsDivider()
            navRow("Change password") { route = .changePassword }
            SettingsDivider()
            Button { showSignOut = true } label: {
                SettingsRow(title: "Sign out") { EmptyView() }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button { route = .deleteAccount } label: {
                HStack {
                    Text("Delete account")
                        .font(LumisTypography.bodyLarge)
                        .foregroundStyle(LumisColors.destructive)
                    Spacer()
                    SettingsChevron()
                }
                .settingsRowPadding()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About

    @State private var safariURL: URL?
    @State private var showFeedback = false

    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow(title: "Version") {
                SettingsDetailText("\(LumisConfig.appVersion) (\(LumisConfig.buildNumber))")
            }
            SettingsDivider()
            navRow("Privacy policy") { safariURL = URL(string: LumisConfig.privacyPolicyURL) }
            SettingsDivider()
            navRow("Terms of service") { safariURL = URL(string: LumisConfig.termsURL) }
            SettingsDivider()
            navRow("Send feedback") { showFeedback = true }
        }
        // Refresh connection status on dismiss — the user may have just
        // finished the Google consent flow in this sheet.
        .sheet(item: $safariURL,
               onDismiss: { Task { await servicesVM.fetchStatus() } }) { url in
            SafariView(url: url).ignoresSafeArea()
        }
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
            SettingsRow(title: title) { SettingsChevron() }
        }
        .buttonStyle(.plain)
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
                ? "\(result.cookieCount) cookies found. Sync looks good."
                : "No cookies found. Reconnect in the extension."
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
        SettingsRow(icon: ws.connected ? "checkmark.circle" : "circle.dashed",
                    title: ws.connected ? "Connected to Lumis" : "Connecting to Lumis…",
                    subtitle: ws.connected
                        ? "This phone is receiving live updates."
                        : "Trying to reach the Lumis server.") {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The honest phone ↔ extension link status shown at the top of Connected
/// Services. Only ever says "not set up" when the backend confirmed it —
/// while checking or unreachable it says that instead. Same wording as the
/// extension popup. `staleNote` appears when the shown data is a cached
/// answer because the last refresh failed.
struct ExtensionSyncBanner: View {
    let state: ExtensionSyncState
    var staleNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LumisSpacing.md) {
                Image(systemName: state.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.color)
                    .frame(width: 29, height: 29)
                    .background(LumisColors.textPrimary.opacity(0.08),
                                in: LumisRadius.rect(7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(LumisTypography.bodyLarge)
                        .foregroundStyle(LumisColors.textPrimary)
                    Text(state.detail)
                        .font(LumisTypography.caption)
                        .foregroundStyle(LumisColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .settingsRowPadding()
            .frame(minHeight: 44)
            if let staleNote {
                Text("\(staleNote) — showing the last known state.")
                    .font(LumisTypography.caption)
                    .foregroundStyle(LumisColors.textTertiary)
                    .padding(.leading, LumisSpacing.lg + 29 + LumisSpacing.md)
                    .padding(.bottom, 11)
                    .padding(.top, -4)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Trailing status for a service row: a small state dot plus quiet detail
/// text, in Apple's Settings idiom (color as reinforcement, words as truth).
struct ServiceStatusLabel: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected ? LumisColors.textSecondary : LumisColors.textTertiary)
                .frame(width: 7, height: 7)
            Text(connected ? "Connected" : "Not connected")
                .font(LumisTypography.bodyMedium)
                .foregroundStyle(LumisColors.textSecondary)
        }
        .accessibilityLabel(connected ? "Connected" : "Not connected")
    }
}
