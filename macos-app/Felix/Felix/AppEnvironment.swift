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

    @AppStorage(FelixBrand.backendURLKey) var backendURL: String = FelixBrand.defaultBackendURL
    @AppStorage(FelixBrand.notifyCompletionKey) var notifyCompletion = true
    @AppStorage(FelixBrand.notifyErrorsKey) var notifyErrors = true

    let feed = EventFeed()

    /// Last few actions, kept fresh for the menu-bar popover.
    @Published var recentActions: [ActionHistoryItem] = []

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
        Task { await refreshRecent() }
    }

    func refreshRecent() async {
        if let items = try? await APIService.history() {
            recentActions = Array(items.prefix(3))
        }
    }

    func reconnect() {
        feed.restart()
        Task { await refreshRecent() }
    }
}
