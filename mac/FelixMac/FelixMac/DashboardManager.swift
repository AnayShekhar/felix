import Foundation
import AppKit

@MainActor
final class DashboardManager: ObservableObject {
    @Published private(set) var running = false

    private var process: Process?

    func start(repoRoot: URL) {
        guard !running else { return }

        let webDir = repoRoot.appendingPathComponent("web")
        guard FileManager.default.fileExists(atPath: webDir.appendingPathComponent("package.json").path) else {
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npm", "run", "dev", "--", "-p", "3000"]
        proc.currentDirectoryURL = webDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        do {
            try proc.run()
            process = proc
            running = true
        } catch {
            // Dashboard is optional — backend still works without it.
        }
    }

    func openInBrowser() {
        NSWorkspace.shared.open(URL(string: "http://localhost:3000")!)
    }

    func stop() {
        process?.terminate()
        process = nil
        running = false
    }
}
