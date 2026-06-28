import Combine
import Foundation
import SwiftUI

/// Whether the linked Mac is reachable. Drives banners, the Home status dot,
/// and the Settings Mac row.
enum MacConnectionState: Equatable {
    case linkedOnline      // linked and reachable
    case linkedOffline     // linked, no heartbeat in >30s
    case unlinked          // no Mac paired
    case linking           // pairing in progress
}

/// `GET /link/status` response.
struct LinkStatus: Codable {
    let linked: Bool
    let macId: String?
    let macName: String?
    let macOnline: Bool?
    let linkedAt: Double?
    let lastSeen: Double?
}

private struct PairResult: Codable {
    let macId: String
    let macName: String?
}

/// Owns the iPhone's view of the linked Mac. Polls `/link/status` every 15s
/// while the app is foregrounded.
@MainActor
final class MacConnectionViewModel: ObservableObject {
    @Published var connectionState: MacConnectionState = .unlinked
    @Published var macName: String?
    @Published var lastSeen: Date?
    @Published var linkedAt: Date?

    private var pollTask: Task<Void, Never>?
    private var token: String? { KeychainManager.token }

    // MARK: - Polling lifecycle

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Status

    func refresh() async {
        guard let token else { connectionState = .unlinked; return }
        guard let status = try? await LumisAPI.request("/link/status", token: token, as: LinkStatus.self) else {
            return  // keep last known state on a network blip
        }
        apply(status)
    }

    private func apply(_ status: LinkStatus) {
        macName = status.macName
        lastSeen = status.lastSeen.map { Date(timeIntervalSince1970: $0) }
        linkedAt = status.linkedAt.map { Date(timeIntervalSince1970: $0) }
        if !status.linked {
            connectionState = .unlinked
        } else {
            connectionState = (status.macOnline ?? false) ? .linkedOnline : .linkedOffline
        }
    }

    // MARK: - Pairing

    /// Submit a 6-char code. Returns true on success.
    func pair(code: String) async -> Bool {
        guard let token else { return false }
        connectionState = .linking
        do {
            let result = try await LumisAPI.request(
                "/link/pair", method: "POST", body: ["code": code], token: token, as: PairResult.self
            )
            macName = result.macName
            connectionState = .linkedOnline
            Haptics.success()
            return true
        } catch {
            await refresh()  // restore prior state
            Haptics.error()
            return false
        }
    }

    func unpair() async {
        guard let token else { return }
        _ = try? await LumisAPI.requestVoid("/link/unpair", method: "DELETE", token: token)
        connectionState = .unlinked
        macName = nil
        lastSeen = nil
    }

    /// "Reconnect" affordance: force an immediate status re-check.
    func reconnect() async {
        await refresh()
    }
}
