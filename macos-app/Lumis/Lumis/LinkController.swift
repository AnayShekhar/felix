import Foundation
import AppKit

/// Owns the Mac side of phone↔Mac pairing. While the popover is open and the
/// user is signed in, it asks the backend for a 6-digit code (account-bound)
/// and polls the real pairing status — so the UI reflects whether a phone on
/// the SAME account has actually confirmed the connection, not a global flag.
///
/// The Mac is identified by the same `~/.lumis/mac_id` file the local agent
/// uses, so the agent's heartbeats and this app's pairing line up.
@MainActor
final class LinkController: ObservableObject {
    @Published var linked = false
    @Published var macOnline = false
    @Published var code: String?
    @Published var error: String?

    private let macID: String = LinkController.loadMacID()
    private let macName: String = Host.current().localizedName ?? "Mac"
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard APIService.token != nil else {
            linked = false; code = nil; macOnline = false
            return
        }
        guard let status = try? await APIService.linkStatus() else { return }
        linked = status.linked
        macOnline = status.macOnline ?? false
        if status.linked {
            code = nil
            try? await APIService.heartbeat(macId: macID, macName: macName)
        } else if code == nil {
            await generate()
        }
    }

    func generate() async {
        do {
            code = try await APIService.generateLinkCode(macId: macID, macName: macName).code
            error = nil
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stable per-machine id, shared with the local agent (`~/.lumis/mac_id`).
    private static func loadMacID() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lumis")
        let file = dir.appendingPathComponent("mac_id")
        if let id = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        let new = UUID().uuidString
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? new.write(to: file, atomically: true, encoding: .utf8)
        return new
    }
}
