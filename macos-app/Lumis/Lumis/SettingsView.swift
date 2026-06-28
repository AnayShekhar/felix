import SwiftUI

/// Settings view: backend URL, test connection, launch at login, show-in-Dock,
/// notification preferences.
struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var urlDraft = ""
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showInDock = false
    @State private var launchError: String?

    enum TestResult {
        case success(Int)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PanelHeader(title: "Settings", subtitle: "Connection and preferences") { EmptyView() }
                    .padding(.horizontal, -20)

                section("Backend") {
                    Text("URL")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("http://localhost:8000", text: $urlDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .onSubmit(saveURL)
                        Button("Save", action: saveURL)
                            .buttonStyle(LumisButtonStyle())
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack(spacing: 6) {
                                if testing { ProgressView().controlSize(.small) }
                                Text("Test Connection")
                            }
                        }
                        .buttonStyle(LumisButtonStyle())
                        .disabled(testing)

                        switch testResult {
                        case .success(let ms):
                            Label("Connected · \(ms) ms", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LumisBrand.online)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LumisBrand.error)
                        case nil:
                            EmptyView()
                        }
                        Spacer()
                    }
                }

                section("Startup") {
                    Toggle(isOn: $launchAtLogin) {
                        settingLabel("Launch at login", "Start Lumis automatically when you log in.")
                    }
                    .toggleStyle(.switch).tint(LumisBrand.accent)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let result = LaunchAtLogin.set(newValue)
                        if !result.ok {
                            launchError = result.message
                            launchAtLogin = LaunchAtLogin.isEnabled
                        } else {
                            launchError = nil
                        }
                    }
                    if let launchError {
                        Text(launchError).font(.system(size: 11)).foregroundStyle(LumisBrand.error)
                    }

                    Toggle(isOn: $showInDock) {
                        settingLabel("Show in Dock", "Restart Lumis with a Dock icon. Off keeps it menu-bar only.")
                    }
                    .toggleStyle(.switch).tint(LumisBrand.accent)
                    .onChange(of: showInDock) { _, newValue in
                        applyDockVisibility(newValue)
                    }
                }

                section("Notifications") {
                    Toggle(isOn: env.$notifyCompletion) {
                        settingLabel("Task completion", "Notify when Lumis finishes a workflow or task.")
                    }
                    .toggleStyle(.switch).tint(LumisBrand.accent)
                    Toggle(isOn: env.$notifyErrors) {
                        settingLabel("Errors", "Notify when a tool fails.")
                    }
                    .toggleStyle(.switch).tint(LumisBrand.accent)
                }

                section("About") {
                    HStack {
                        Text("Lumis Dashboard").font(.system(size: 13, weight: .heavy))
                        Spacer()
                        Text("v\(LumisBrand.appVersion)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            urlDraft = env.backendURL
            showInDock = (NSApp.activationPolicy() == .regular)
        }
    }

    // MARK: Sections + helpers

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(1.1)
                .foregroundStyle(LumisBrand.accent)
            content()
        }
        .lumisCard(padding: 16)
    }

    private func settingLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .heavy))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func saveURL() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        env.backendURL = trimmed.isEmpty ? LumisBrand.defaultBackendURL : trimmed
        urlDraft = env.backendURL
        testResult = nil
        env.reconnect()
    }

    private func testConnection() async {
        saveURL()
        testing = true
        testResult = nil
        do {
            let ms = try await APIService.health()
            testResult = .success(ms)
        } catch let e as APIError {
            testResult = .failure(e.message)
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        testing = false
    }

    /// "Show in Dock" toggles the activation policy live (the LSUIElement
    /// equivalent at runtime — no relaunch needed).
    private func applyDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Compact filled accent button used in Settings.
struct LumisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(LumisBrand.accent.opacity(configuration.isPressed ? 0.5 : 0.9),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(.black)
    }
}
