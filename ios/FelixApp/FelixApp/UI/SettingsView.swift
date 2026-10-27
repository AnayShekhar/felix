import SwiftUI

/// Settings, in the visual language of Apple's own Settings app: plain
/// inset-grouped sections with uniform leading icon chips, hairline inset
/// separators, muted section headers/footers, a consistent 44pt row rhythm,
/// and the accent color reserved for interactive elements (toggles, links,
/// the Connect action). The profile summary at the top is the single
/// stronger visual container on the screen.
struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var felixVM: FelixViewModel

    /// When presented as the full-screen sheet from the sidebar, this provides
    /// the leading "X" that returns to the sidebar.
    var onClose: (() -> Void)?

    // Persisted preferences (only ones wired to real behavior).
    @AppStorage("lumis.pref.wakeWord") private var wakeWord = true
    @AppStorage(FelixAppearance.storageKey) private var appearanceRaw = FelixAppearance.system.rawValue

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
                FelixColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: FelixSpacing.xl) {
                        profileCard
                        connectedServicesSection
                        appearanceSection
                        voiceSection
                        MemorySection()
                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, FelixSpacing.screenMargin)
                    .padding(.top, FelixSpacing.sm)
                    .padding(.bottom, 110)
                }
                .refreshable { await servicesVM.fetchStatus() }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onClose() } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FelixColors.textPrimary)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.felixPress)
                        .felixGlass(in: Circle(), interactive: true)
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
            .onReceive(felixVM.ws.events) { env in
                if env.event == "connect_status_changed" {
                    Task { await servicesVM.fetchStatus() }
                }
            }
            .confirmationDialog("Sign out of Felix?", isPresented: $showSignOut, titleVisibility: .visible) {
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
                    Circle().fill(FelixColors.tint).frame(width: 52, height: 52)
                    Text(authVM.currentUser?.initials ?? "?")
                        .font(FelixTypography.bodyLargeEmphasized)
                        .foregroundStyle(FelixColors.onTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // Medium, not semibold — the "Settings" large title is this
                    // screen's one dominant heading.
                    Text(authVM.currentUser?.displayName ?? "Your account")
                        .font(FelixTypography.bodyLargeEmphasized)
                        .foregroundStyle(FelixColors.textPrimary)
                    Text(authVM.currentUser?.email ?? "")
                        .font(FelixTypography.bodySmall)
                        .foregroundStyle(FelixColors.textSecondary)
                }
                Spacer()
                SettingsChevron()
            }
            .padding(FelixSpacing.lg)
            .background(FelixColors.tintWash, in: FelixRadius.rect(FelixRadius.card))
            .felixGlass(in: FelixRadius.rect(FelixRadius.card), interactive: true)
            .shadow(color: FelixColors.shadow, radius: 8, y: 4)
        }
        .buttonStyle(.felixPress)
    }

    // MARK: - Connected services (Chrome extension)

    @ViewBuilder
    private var connectedServicesSection: some View {
        SettingsSection(
            "Connected services",
            footer: "Accounts are connected on your computer through the Felix browser extension. Google API access is granted here."
        ) {
            // Connection status lives exclusively here — never on the main screen.
            ServerStatusRow(ws: felixVM.ws)
            SettingsDivider(hasIcon: true)
            ExtensionSyncBanner(state: servicesVM.syncState,
                                staleNote: servicesVM.errorMessage)
            SettingsDivider(hasIcon: true)
            // Google OAuth (API access) — what Gmail/Sheets/Calendar tools run
            // on. Separate from the cookie rows: cookies sign the cloud
            // browser in; this grants Felix the Google APIs themselves.
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
                HStack(spacing: FelixSpacing.sm) {
                    Button(verifyingID == service.id ? "Checking…" : "Verify") {
                        Task { await verify(service.id) }
                    }
                    .font(FelixTypography.captionMedium)
                    .foregroundStyle(FelixColors.tintStrong)
                    .disabled(verifyingID == service.id)
                    if let msg = verifyMessages[service.id] {
                        Text(msg)
                            .font(FelixTypography.caption)
                            .foregroundStyle(FelixColors.textTertiary)
                    }
                }
                // Aligns with the text column (16 margin + 29 chip + 12 gap).
                .padding(.leading, FelixSpacing.lg + 29 + FelixSpacing.md)
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
                        .font(FelixTypography.bodyMedium)
                        .foregroundStyle(FelixColors.tintStrong)
                }
            }
            if let googleConnectError {
                Text(googleConnectError)
                    .font(FelixTypography.caption)
                    .foregroundStyle(FelixColors.destructive)
                    .padding(.leading, FelixSpacing.lg + 29 + FelixSpacing.md)
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
                safariURL = try await APIClient.googleConnectURL(baseURL: FelixConfig.backendURL)
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
                    ForEach(FelixAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(FelixColors.textSecondary)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        SettingsSection(
            "Voice",
            footer: "Saying \u{201C}Hey Felix\u{201D} is the only way to start a voice request — there is no microphone button."
        ) {
            SettingsRow(icon: "waveform",
                        title: "\u{201C}Hey Felix\u{201D}",
                        subtitle: "Listen for your wake word in the background") {
                Toggle("", isOn: $wakeWord)
                    .labelsHidden()
                    .tint(FelixColors.tint)
            }
            .onChange(of: wakeWord) { _, on in felixVM.setWakeWord(on) }
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
                        .font(FelixTypography.bodyLarge)
                        .foregroundStyle(FelixColors.destructive)
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
                SettingsDetailText("\(FelixConfig.appVersion) (\(FelixConfig.buildNumber))")
            }
            SettingsDivider()
            navRow("Privacy policy") { safariURL = URL(string: FelixConfig.privacyPolicyURL) }
            SettingsDivider()
            navRow("Terms of service") { safariURL = URL(string: FelixConfig.termsURL) }
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
                MailView(recipient: FelixConfig.supportEmail, subject: "Felix Feedback")
            } else {
                Text("No mail account is set up on this device.")
                    .font(FelixTypography.bodyMedium).padding()
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
            let result = try await FelixAPI.request(
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
                    title: ws.connected ? "Connected to Felix" : "Connecting to Felix…",
                    subtitle: ws.connected
                        ? "This phone is receiving live updates."
                        : "Trying to reach the Felix server.") {
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
            HStack(spacing: FelixSpacing.md) {
                Image(systemName: state.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.color)
                    .frame(width: 29, height: 29)
                    .background(FelixColors.surfaceProminent,
                                in: FelixRadius.rect(7))
                    .overlay(FelixRadius.rect(7).stroke(FelixColors.glassStroke, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(FelixTypography.bodyLarge)
                        .foregroundStyle(FelixColors.textPrimary)
                    Text(state.detail)
                        .font(FelixTypography.caption)
                        .foregroundStyle(FelixColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .settingsRowPadding()
            .frame(minHeight: 44)
            if let staleNote {
                Text("\(staleNote) — showing the last known state.")
                    .font(FelixTypography.caption)
                    .foregroundStyle(FelixColors.textTertiary)
                    .padding(.leading, FelixSpacing.lg + 29 + FelixSpacing.md)
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
                .fill(connected ? FelixColors.textSecondary : FelixColors.textTertiary)
                .frame(width: 7, height: 7)
            Text(connected ? "Connected" : "Not connected")
                .font(FelixTypography.bodyMedium)
                .foregroundStyle(FelixColors.textSecondary)
        }
        .accessibilityLabel(connected ? "Connected" : "Not connected")
    }
}
