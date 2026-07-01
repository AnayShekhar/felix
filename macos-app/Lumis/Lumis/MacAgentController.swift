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
    /// True while the one-time Playwright browser download is running, so the
    /// dashboard can show "Setting up browser automation…".
    @Published var settingUpBrowser = false

    /// Override the agent launcher location; defaults to the repo checkout.
    static let scriptPathKey = "lumis.macAgentScript"
    /// Set once the Playwright Chromium download has completed successfully.
    static let playwrightInstalledKey = "lumis.playwrightInstalled"

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

    /// Start the agent (idempotent). Call once on app launch. Runs the one-time
    /// Playwright browser setup first so browser tools work without any Chrome
    /// settings, then spawns the agent process.
    func start() {
        guard !wantRunning else { return }
        wantRunning = true
        Task {
            await ensurePlaywrightInstalled()
            spawn()
        }
    }

    /// One-time: install the Playwright package + Chromium into the backend venv
    /// so browser automation works out of the box. Gated by a UserDefaults flag
    /// so it only runs on the first launch after install. Best-effort — if it
    /// fails the agent still starts; browser tools will simply report the issue.
    func ensurePlaywrightInstalled() async {
        if UserDefaults.standard.bool(forKey: Self.playwrightInstalledKey) { return }
        guard let script = resolveScriptPath() else { return }
        let backend = (script as NSString).deletingLastPathComponent + "/backend"
        let python = "\(backend)/venv/bin/python"
        guard FileManager.default.fileExists(atPath: python) else { return }

        settingUpBrowser = true
        defer { settingUpBrowser = false }

        // Install the pip package (no-op if present), then download Chromium.
        _ = await runShell("\(python.q) -m pip install 'playwright>=1.40.0'")
        let result = await runShell("\(python.q) -m playwright install chromium")
        if result.lowercased().contains("chromium")
            || result.lowercased().contains("already") || result.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.playwrightInstalledKey)
            print("Playwright ready")
        }
    }

    /// Run a shell command and return its combined stdout+stderr.
    private func runShell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = ["-lc", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
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

        // Guarantee a SINGLE agent. Orphans from prior launches (force-quit,
        // crash, manual runs) stay connected to the backend, and a command
        // broadcast would otherwise run on each one — e.g. opening a URL several
        // times. Kill any strays before starting our own.
        killStrayAgents()

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

    /// Terminate any already-running mac_agent.py processes (other than the one
    /// we're about to launch, which isn't running yet). Best-effort; `pkill`
    /// matches the python invocation specifically so it won't hit editors etc.
    private func killStrayAgents() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "python mac_agent.py"]
        try? p.run()
        p.waitUntilExit()
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

private extension String {
    /// Single-quote this string for safe embedding in a `/bin/bash -lc` command.
    var q: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
