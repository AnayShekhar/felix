import Foundation
import Combine

/// Launches and supervises the local Lumis Mac agent (backend/mac_agent.py via
/// run_mac_agent.sh). The agent is the "hands" of the split architecture: the
/// Railway backend (Linux) plans actions but cannot run osascript/pmset/etc., so
/// this local process executes those tools and reports results back over the
/// WebSocket. The authoritative "connected" signal comes from the backend's
/// GET /mac/status; this controller only ensures the process is running.
@MainActor
final class MacAgentController: ObservableObject {
    /// True while our launched agent process is alive (it self-launched OK).
    @Published var processRunning = false
    /// Surfaced inline if we couldn't locate or start the agent script.
    @Published var launchError: String?

    /// Override the agent launcher location; defaults to the repo checkout.
    static let scriptPathKey = "lumis.macAgentScript"

    private var process: Process?
    private var restartWorkItem: DispatchWorkItem?
    private var wantRunning = false

    /// Locate run_mac_agent.sh. The repo may be checked out under any name
    /// (e.g. "felix" or "lumis") in any of the usual dev folders, so we try the
    /// common spots and then shallow-scan for the script. `fileExists` (not
    /// `isExecutableFile`) because we launch it via `/bin/bash <script>`.
    private func resolveScriptPath() -> String? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: Self.scriptPathKey),
           !custom.trimmingCharacters(in: .whitespaces).isEmpty,
           fm.fileExists(atPath: custom) {
            return custom
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["\(home)/Documents", home, "\(home)/Developer",
                     "\(home)/Desktop", "\(home)/Projects", "\(home)/Code"]
        let names = ["felix", "lumis", "Felix", "Lumis"]

        // 1. Exact known locations.
        for root in roots {
            for name in names {
                let path = "\(root)/\(name)/run_mac_agent.sh"
                if fm.fileExists(atPath: path) { return path }
            }
        }
        // 2. Shallow scan: any checkout directly under a dev root.
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let path = "\(root)/\(entry)/run_mac_agent.sh"
                if fm.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Start the agent (idempotent). Call once on app launch.
    func start() {
        guard !wantRunning else { return }
        wantRunning = true
        spawn()
    }

    /// Stop supervising and terminate the agent (called on app quit).
    func stop() {
        wantRunning = false
        restartWorkItem?.cancel()
        process?.terminate()
        process = nil
        processRunning = false
    }

    private func spawn() {
        guard wantRunning, process == nil else { return }
        guard let script = resolveScriptPath() else {
            launchError = "Couldn't find run_mac_agent.sh. Set its path in Settings or run it manually."
            processRunning = false
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script]
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.handleTermination() }
        }

        do {
            try proc.run()
            process = proc
            processRunning = true
            launchError = nil
        } catch {
            launchError = "Couldn't start the Mac agent: \(error.localizedDescription)"
            processRunning = false
        }
    }

    private func handleTermination() {
        process = nil
        processRunning = false
        guard wantRunning else { return }
        // The agent script exited unexpectedly — relaunch after a short delay.
        let work = DispatchWorkItem { [weak self] in self?.spawn() }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
