import SwiftUI
import Combine

enum DashboardSection: String, CaseIterable, Identifiable {
    case activity, memory, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: return "Activity"
        case .memory:   return "Memory"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .activity: return "bolt.fill"
        case .memory:   return "brain"
        case .settings: return "gearshape.fill"
        }
    }
}

/// App-wide observable state shared by the popover and the dashboard window.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published var section: DashboardSection = .activity
    @Published var feedCollapsed = false

    @AppStorage(LumisBrand.backendURLKey) var backendURL: String = LumisBrand.defaultBackendURL
    @AppStorage(LumisBrand.notifyCompletionKey) var notifyCompletion = true
    @AppStorage(LumisBrand.notifyErrorsKey) var notifyErrors = true

    let feed = EventFeed()

    /// Supervises the local Mac agent process (the "hands" of the system).
    let macAgent = MacAgentController()

    /// Last few actions, kept fresh for the menu-bar popover.
    @Published var recentActions: [ActionHistoryItem] = []

    /// Whether the backend currently has a Mac agent connected (GET /mac/status).
    @Published var macAgentConnected = false

    private var macStatusTimer: Timer?

    init() {
        feed.onEvent = { [weak self] event, _ in
            guard let self else { return }
            Notifier.handle(event, notifyCompletion: self.notifyCompletion,
                            notifyErrors: self.notifyErrors)
            // A finished workflow likely changed history — refresh the popover.
            if event.event == "workflow_complete" || event.event == "action_undone" {
                Task { await self.refreshRecent() }
            }
        }
        feed.start()
        // Start the local Mac agent so macOS-local tools can run.
        macAgent.start()
        Task { await refreshRecent() }
        startMacStatusPolling()
    }

    func refreshRecent() async {
        if let items = try? await APIService.history() {
            recentActions = Array(items.prefix(3))
        }
    }

    /// Poll GET /mac/status so the popover reflects the agent's real backend state.
    private func startMacStatusPolling() {
        Task { await refreshMacStatus() }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshMacStatus() }
        }
        macStatusTimer = timer
    }

    func refreshMacStatus() async {
        if let connected = try? await APIService.macConnected() {
            macAgentConnected = connected
        } else {
            macAgentConnected = false
        }
    }

    func reconnect() {
        feed.restart()
        Task {
            await refreshRecent()
            await refreshMacStatus()
        }
    }
}
