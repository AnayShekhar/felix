import Foundation
import Combine

@MainActor
final class WebSocketClient: ObservableObject {
    @Published var latest: StepResult?
    @Published var connected = false
    @Published var working = false
    @Published var activeTask: TaskState?   // live background task (Phase 5)

    private var task: URLSessionWebSocketTask?
    private var wantConnection = false
    private var currentURL: URL?

    func connect(to wsURL: URL) {
        if currentURL == wsURL, task != nil { return }
        disconnect()
        wantConnection = true
        currentURL = wsURL
        let t = URLSession.shared.webSocketTask(with: wsURL)
        task = t
        t.resume()
        verifyConnection()
        receive()
    }

    private func verifyConnection() {
        task?.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.wantConnection else { return }
                if error != nil {
                    self.handleDisconnect()
                } else {
                    self.connected = true
                }
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
        switch env.event {
        case "step_started":
            working = true
        case "step_executed":
            if let d = env.data {
                latest = StepResult(tool: d.tool, status: d.status, message: d.message,
                                    title: d.title, detail: d.detail, url: d.url)
            }
        case "workflow_complete":
            working = false
            if let last = env.data?.steps?.last { latest = last }
        case "task_started":
            if let id = env.data?.task_id {
                activeTask = TaskState(id: id,
                                       instruction: env.data?.instruction ?? "Working…",
                                       status: env.data?.status ?? "running",
                                       progressPct: 0)
            }
        case "task_progress":
            if let id = env.data?.task_id {
                if activeTask?.id != id {
                    activeTask = TaskState(id: id, instruction: "Working…",
                                           status: "running", progressPct: 0)
                }
                activeTask?.status = "running"
                activeTask?.progressPct = env.data?.progress_pct ?? activeTask?.progressPct ?? 0
            }
        case "task_complete":
            if let id = env.data?.task_id, activeTask?.id == id {
                activeTask?.status = env.data?.status ?? "done"
                activeTask?.progressPct = env.data?.progress_pct ?? 100
                // Clear the finished task shortly after so the UI can show 100%.
                let finishedID = id
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if self.activeTask?.id == finishedID { self.activeTask = nil }
                }
            }
        default:
            break
        }
    }

    private func handleDisconnect() {
        connected = false
        task = nil
        guard wantConnection, let url = currentURL else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.wantConnection, self.currentURL == url {
                self.connect(to: url)
            }
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
