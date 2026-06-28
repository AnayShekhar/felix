import SwiftUI

/// Settings view: account, startup, notifications, about.
struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var auth: AuthStore

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PanelHeader(title: "Settings", subtitle: "Account and preferences") { EmptyView() }
                    .padding(.horizontal, -20)

                section("Account") {
                    HStack(spacing: 12) {
                        Text(auth.initials.isEmpty ? "?" : auth.initials)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(LumisBrand.ink)
                            .frame(width: 40, height: 40)
                            .background(LumisBrand.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(auth.displayName.isEmpty ? "Signed in" : auth.displayName)
                                .font(.system(size: 13, weight: .heavy))
                            Text(auth.email).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sign Out") { auth.signOut() }
                            .buttonStyle(LumisButtonStyle())
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
    }

    // MARK: Sections + helpers

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1)
                .foregroundStyle(LumisBrand.ink.opacity(0.5))
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
}

/// Compact filled accent button used in Settings.
struct LumisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(LumisBrand.accent.opacity(configuration.isPressed ? 0.5 : 0.9),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(LumisBrand.ink)
    }
}
