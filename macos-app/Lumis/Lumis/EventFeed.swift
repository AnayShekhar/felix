import Foundation
import Combine

/// Live WebSocket connection to the backend's /ws stream. Drives the
/// connection status dot, the right-panel event feed, and notifications.
@MainActor
final class EventFeed: ObservableObject {
    @Published var connected = false
    @Published var events: [FeedEvent] = []
    @Published var lastError: String?

    /// Set by the dashboard so the feed can post notifications on completion.
    var onEvent: ((FeedEvent, _ event: String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var wantConnection = false
    private var currentURL: URL?
    private let maxEvents = 200

    func start() {
        let base = (UserDefaults.standard.string(forKey: LumisBrand.backendURLKey)
                    ?? LumisBrand.defaultBackendURL)
        let ws = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let u = URL(string: "\(ws)/ws") else {
            lastError = "Invalid backend URL for WebSocket."
            return
        }
        connect(to: u)
    }

    /// Reconnect after the backend URL changes in Settings.
    func restart() {
        disconnect()
        start()
    }

    func clear() { events.removeAll() }

    private func connect(to wsURL: URL) {
        if currentURL == wsURL, task != nil { return }
        disconnect()
        wantConnection = true
        currentURL = wsURL
        let t = URLSession.shared.webSocketTask(with: wsURL)
        task = t
        t.resume()
        ping()
        receive()
    }

    private func ping() {
        task?.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.wantConnection else { return }
                if error != nil { self.handleDisconnect() }
                else { self.connected = true; self.lastError = nil }
            }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let env = try? JSONDecoder().decode(WSEnvelope.self, from: data) {
                    Task { @MainActor in self.handle(env) }
                }
                self.receive()
            case .failure:
                Task { @MainActor in self.handleDisconnect() }
            }
        }
    }

    private func handle(_ env: WSEnvelope) {
        connected = true
        guard let event = env.event else { return }
        let d = env.data

        // Only render meaningful events as feed cards.
        let renderable: Set<String> = [
            "step_executed", "workflow_complete", "action_undone",
            "task_started", "task_progress", "task_complete"
        ]
        guard renderable.contains(event) else { return }

        let tool = d?.tool ?? d?.steps?.last?.tool
        let status = d?.status ?? d?.steps?.last?.status
        let message = feedMessage(event: event, data: d)

        let feedEvent = FeedEvent(
            event: event,
            tool: tool,
            status: status,
            message: message,
            receivedAt: Date()
        )
        events.append(feedEvent)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        onEvent?(feedEvent, event)
    }

    private func feedMessage(event: String, data: WSData?) -> String {
        switch event {
        case "workflow_complete":
            if let last = data?.steps?.last {
                return ToolSummary.line(title: last.title, message: last.message, tool: last.tool)
            }
            return "Workflow complete"
        case "action_undone":
            return data?.message ?? "Action undone"
        case "task_started":
            return data?.instruction ?? "Task started"
        case "task_progress":
            return "Working… \(data?.progress_pct ?? 0)%"
        case "task_complete":
            return "Task \(data?.status ?? "done")"
        default:
            return ToolSummary.line(title: data?.title, message: data?.message, tool: data?.tool)
        }
    }

    private func handleDisconnect() {
        connected = false
        task = nil
        guard wantConnection, let url = currentURL else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.wantConnection, self.currentURL == url { self.connect(to: url) }
        }
    }

    func disconnect() {
        wantConnection = false
        currentURL = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }
}
