import Foundation
import Combine

@MainActor
final class WebSocketClient: ObservableObject {
    @Published var latest: StepResult?
    @Published var connected = false
    @Published var working = false

    private var task: URLSessionWebSocketTask?
    private var wantConnection = false

    func connect() {
        wantConnection = true
        guard task == nil else { return }
        let t = URLSession.shared.webSocketTask(with: Config.wsURL)
        task = t
        t.resume()
        connected = true
        receive()
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
                self.receive() // keep listening
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
        default:
            break
        }
    }

    private func handleDisconnect() {
        connected = false
        task = nil
        guard wantConnection else { return }
        // Auto-reconnect after a short delay.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.wantConnection { self.connect() }
        }
    }

    func disconnect() {
        wantConnection = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }
}
