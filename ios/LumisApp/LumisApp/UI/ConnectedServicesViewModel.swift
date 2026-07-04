import Foundation
import Combine
import SwiftUI

/// One connectable service, matching the backend's service identifiers.
struct ServiceDefinition: Identifiable {
    let id: String            // "gmail", "sheets", "notion", … (matches backend)
    let displayName: String
    let icon: String          // SF Symbol
    let description: String
}

let SUPPORTED_SERVICES: [ServiceDefinition] = [
    ServiceDefinition(id: "gmail",    displayName: "Gmail",         icon: "envelope.fill",         description: "Read and draft emails"),
    ServiceDefinition(id: "sheets",   displayName: "Google Sheets", icon: "tablecells.fill",       description: "Track expenses and data"),
    ServiceDefinition(id: "notion",   displayName: "Notion",        icon: "doc.text.fill",         description: "Create and edit pages"),
    ServiceDefinition(id: "linkedin", displayName: "LinkedIn",      icon: "person.crop.circle",    description: "Search and post updates"),
    ServiceDefinition(id: "slack",    displayName: "Slack",         icon: "message.fill",          description: "Send messages"),
    ServiceDefinition(id: "airtable", displayName: "Airtable",      icon: "square.grid.3x3.fill",  description: "Manage records"),
]

/// Response of `GET /connect/status`.
struct ConnectStatusResponse: Codable {
    let connected: [String]
    // Sync-freshness fields (older backends omit them — keep optional).
    let services: [ServiceSync]?
    let everSynced: Bool?
    let lastSyncedAt: Double?

    struct ServiceSync: Codable {
        let service: String
        let lastSyncedAt: Double?
        enum CodingKeys: String, CodingKey {
            case service
            case lastSyncedAt = "last_synced_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case connected, services
        case everSynced = "ever_synced"
        case lastSyncedAt = "last_synced_at"
    }
}

/// The honest tri-state of the phone ↔ Chrome-extension link. Mirrored by the
/// extension popup so both surfaces read as the same feature.
enum ExtensionSyncState: Equatable {
    /// The extension has never synced anything for this account.
    case neverConnected
    /// Synced within the last day — sessions should be fresh.
    case recentlySynced(Date)
    /// Synced once, but a while ago — cookies may have expired.
    case stale(Date)

    static let staleAfter: TimeInterval = 24 * 60 * 60

    static func from(everSynced: Bool, lastSyncedAt: Double?) -> ExtensionSyncState {
        guard everSynced, let ts = lastSyncedAt else { return .neverConnected }
        let date = Date(timeIntervalSince1970: ts)
        return Date().timeIntervalSince(date) < staleAfter
            ? .recentlySynced(date) : .stale(date)
    }

    var title: String {
        switch self {
        case .neverConnected:  return "Extension not connected"
        case .recentlySynced:  return "Extension connected"
        case .stale:           return "Extension needs a refresh"
        }
    }

    var detail: String {
        switch self {
        case .neverConnected:
            return "Install the Lumis Chrome extension on your computer and connect an account."
        case .recentlySynced(let date):
            return "Last synced \(RelativeTime.friendly(date.timeIntervalSince1970))."
        case .stale(let date):
            return "Last synced \(RelativeTime.friendly(date.timeIntervalSince1970)). Open the extension to re-sync your accounts."
        }
    }

    var color: Color {
        switch self {
        case .neverConnected:  return LumisColors.textTertiary
        case .recentlySynced:  return LumisColors.success
        case .stale:           return LumisColors.amber
        }
    }

    var icon: String {
        switch self {
        case .neverConnected:  return "circle.dashed"
        case .recentlySynced:  return "checkmark.circle.fill"
        case .stale:           return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class ConnectedServicesViewModel: ObservableObject {
    @Published var connectedServiceIds: Set<String> = []
    @Published var syncState: ExtensionSyncState = .neverConnected
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchStatus() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await LumisAPI.request(
                "/connect/status",
                token: KeychainManager.token,
                as: ConnectStatusResponse.self
            )
            connectedServiceIds = Set(response.connected)
            syncState = ExtensionSyncState.from(
                everSynced: response.everSynced ?? !response.connected.isEmpty,
                lastSyncedAt: response.lastSyncedAt
            )
        } catch {
            errorMessage = "Couldn't load connected services"
        }
        isLoading = false
    }

    func isConnected(_ serviceId: String) -> Bool {
        connectedServiceIds.contains(serviceId)
    }

    var hasAnyConnection: Bool { !connectedServiceIds.isEmpty }
}
