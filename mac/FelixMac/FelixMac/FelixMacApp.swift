import SwiftUI

@MainActor
final class FelixController: ObservableObject {
    static let shared = FelixController()

    let backend = BackendManager()
    let dashboard = DashboardManager()
    let bonjour = BonjourAdvertiser()

    @Published var setupError: String?
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    private var repoRoot: URL?
    private var didBoot = false

    func boot(openDashboard: Bool = false) {
        if didBoot {
            if openDashboard { dashboard.openInBrowser() }
            return
        }
        didBoot = true

        guard let root = RepoLocator.findRepoRoot() else {
            setupError = "Could not find Felix. Run mac/install.sh once from the repo."
            return
        }
        repoRoot = root
        backend.start(repoRoot: root)
        bonjour.start(port: backend.portNumber)
        dashboard.start(repoRoot: root)
        if openDashboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.dashboard.openInBrowser()
            }
        }

        if UserDefaults.standard.bool(forKey: "felixEnableLoginAtInstall") {
            UserDefaults.standard.set(false, forKey: "felixEnableLoginAtInstall")
            setLaunchAtLogin(true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func restart() {
        guard let root = repoRoot else { boot(); return }
        shutdown()
        backend.start(repoRoot: root)
        bonjour.start(port: backend.portNumber)
        dashboard.start(repoRoot: root)
    }

    func shutdown() {
        bonjour.stop()
        backend.stop()
        dashboard.stop()
    }
}

@main
struct FelixMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var felix = FelixController.shared

    var body: some Scene {
        MenuBarExtra("Felix", systemImage: statusIcon) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Felix Mac")
                    .font(.headline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(felix.backend.running ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let setupError = felix.setupError {
                    Text(setupError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Button("Open Dashboard") {
                    felix.dashboard.openInBrowser()
                }

                Toggle("Start at Login", isOn: Binding(
                    get: { felix.launchAtLogin },
                    set: { felix.setLaunchAtLogin($0) }
                ))

                Button(felix.backend.running ? "Restart Felix" : "Start Felix") {
                    felix.restart()
                }

                Divider()

                Button("Quit Felix") {
                    felix.shutdown()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 260)
        }
        .menuBarExtraStyle(.window)
    }

    private var statusIcon: String {
        felix.backend.running ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusLine: String {
        felix.backend.running
            ? "Running — iPhone can connect on WiFi"
            : "Starting…"
    }
}
