import Foundation
import Combine

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
}

@MainActor
final class ConnectedServicesViewModel: ObservableObject {
    @Published var connectedServiceIds: Set<String> = []
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
