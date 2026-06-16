import Foundation
import Combine

@MainActor
final class WebSocketClient: ObservableObject {
    @Published var latest: StepResult?
    @Published var connected = false
    @Published var working = false

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
