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

// One icon language app-wide: outline SF Symbols only (no .fill variants),
// rendered at a shared size/weight where they appear, so every glyph carries
// the same stroke weight and visual density.
let SUPPORTED_SERVICES: [ServiceDefinition] = [
    ServiceDefinition(id: "gmail",    displayName: "Gmail",         icon: "envelope",          description: "Read and draft emails"),
    ServiceDefinition(id: "sheets",   displayName: "Google Sheets", icon: "tablecells",        description: "Track expenses and data"),
    ServiceDefinition(id: "notion",   displayName: "Notion",        icon: "doc.text",          description: "Create and edit pages"),
    ServiceDefinition(id: "linkedin", displayName: "LinkedIn",      icon: "person.crop.circle", description: "Search and post updates"),
    ServiceDefinition(id: "slack",    displayName: "Slack",         icon: "message",           description: "Send messages"),
    ServiceDefinition(id: "airtable", displayName: "Airtable",      icon: "square.grid.3x3",   description: "Manage records"),
]

/// Response of `GET /connect/status`.
struct ConnectStatusResponse: Codable {
    let connected: [String]
    // Sync-freshness fields (older backends omit them — keep optional).
    let services: [ServiceSync]?
    let everSynced: Bool?
    let lastSyncedAt: Double?
    /// True once the Google OAuth consent flow has stored API tokens — the
    /// credential Gmail/Sheets/Calendar tools actually run on. Separate from
    /// cookie sync (which only signs the cloud browser in).
    let googleApi: Bool?

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
        case googleApi = "google_api"
    }
}

/// The honest state of the phone ↔ Chrome-extension link. "Not connected" is
/// only ever shown when the backend *confirmed* nothing has synced — while
/// loading, or when the check itself fails, the UI says so instead of guessing.
/// Mirrored by the extension popup so both surfaces read as the same feature.
enum ExtensionSyncState: Equatable {
    /// Status request in flight and nothing cached yet.
    case checking
    /// The status check failed and there is no cached answer — unknown, not "off".
    case unavailable
    /// Backend confirmed: this account has never synced anything.
    case neverConnected
    /// Confirmed connected. `lastSynced` is nil on older backends that don't
    /// report timestamps; `fresh` is false once the newest sync is over a day old.
    case connected(lastSynced: Date?, fresh: Bool)

    static let staleAfter: TimeInterval = 24 * 60 * 60

    static func from(_ response: ConnectStatusResponse) -> ExtensionSyncState {
        let everSynced = response.everSynced ?? !response.connected.isEmpty
        guard everSynced else { return .neverConnected }
        guard let ts = response.lastSyncedAt else {
            // Connected, but this backend doesn't report sync times — still
            // connected. (Previously this fell through to "not connected".)
            return .connected(lastSynced: nil, fresh: true)
        }
        let date = Date(timeIntervalSince1970: ts)
        return .connected(lastSynced: date,
                          fresh: Date().timeIntervalSince(date) < staleAfter)
    }

    var title: String {
        switch self {
        case .checking:                       return "Checking extension…"
        case .unavailable:                    return "Can't check right now"
        case .neverConnected:                 return "Extension not set up"
        case .connected(_, true):             return "Extension connected"
        case .connected(_, false):            return "Connected — sync is old"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Asking the Felix server which accounts are linked."
        case .unavailable:
            return "The Felix server didn't answer. Your accounts may still be connected — pull to refresh."
        case .neverConnected:
            return "Install the Felix Chrome extension on your computer and connect an account."
        case .connected(let date, true):
            if let date {
                return "Last synced \(RelativeTime.friendly(date.timeIntervalSince1970))."
            }
            return "Your accounts are linked and ready."
        case .connected(let date, false):
            if let date {
                return "Last synced \(RelativeTime.friendly(date.timeIntervalSince1970)). Open the extension to refresh your sessions."
            }
            return "Open the extension to refresh your sessions."
        }
    }

    // One accent per screen: state is carried by the glyph and the words,
    // never a competing hue — every status icon stays in the neutral greys.
    var color: Color {
        switch self {
        case .checking, .unavailable:  return FelixColors.textTertiary
        case .neverConnected:          return FelixColors.textTertiary
        case .connected(_, true):      return FelixColors.textSecondary
        case .connected(_, false):     return FelixColors.textSecondary
        }
    }

    var icon: String {
        switch self {
        case .checking:              return "ellipsis.circle"
        case .unavailable:           return "questionmark.circle"
        case .neverConnected:        return "circle.dashed"
        case .connected(_, true):    return "checkmark.circle"
        case .connected(_, false):   return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class ConnectedServicesViewModel: ObservableObject {
    @Published var connectedServiceIds: Set<String> = []
    @Published var syncState: ExtensionSyncState = .checking
    /// Per-service last cookie sync, keyed by service id (from `services`).
    @Published var serviceLastSynced: [String: Date] = [:]
    /// Google OAuth (API) connection — what Gmail/Sheets/Calendar tools need.
    @Published var googleAPIConnected = false
    @Published var isLoading = false
    /// Non-nil when the *last* refresh failed; the shown data is the cached
    /// previous answer, never a fabricated "not connected".
    @Published var errorMessage: String?

    private static let cacheKey = "lumis.connectStatus.cache"

    init() {
        // Start from the last confirmed answer so a slow or failed request
        // never flashes "not connected" over a working setup.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(ConnectStatusResponse.self, from: data) {
            apply(cached)
        }
    }

    func fetchStatus() async {
        isLoading = true
        do {
            let response = try await FelixAPI.request(
                "/connect/status",
                token: KeychainManager.token,
                as: ConnectStatusResponse.self
            )
            apply(response)
            errorMessage = nil
            if let data = try? JSONEncoder().encode(response) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } catch {
            // Keep whatever we knew; only downgrade "checking" to "unavailable".
            errorMessage = "Couldn't refresh connection status"
            if syncState == .checking { syncState = .unavailable }
        }
        isLoading = false
    }

    private func apply(_ response: ConnectStatusResponse) {
        connectedServiceIds = Set(response.connected)
        googleAPIConnected = response.googleApi ?? false
        syncState = ExtensionSyncState.from(response)
        var perService: [String: Date] = [:]
        for entry in response.services ?? [] {
            if let ts = entry.lastSyncedAt {
                perService[entry.service] = Date(timeIntervalSince1970: ts)
            }
        }
        serviceLastSynced = perService
    }

    func isConnected(_ serviceId: String) -> Bool {
        connectedServiceIds.contains(serviceId)
    }

    /// "Synced 2 hours ago" caption for a connected service, if known.
    func syncCaption(for serviceId: String) -> String? {
        guard let date = serviceLastSynced[serviceId] else { return nil }
        return "Synced \(RelativeTime.friendly(date.timeIntervalSince1970))"
    }

    var hasAnyConnection: Bool { !connectedServiceIds.isEmpty }
}
