import Foundation
import Combine

@MainActor
final class WebSocketClient: ObservableObject {
    @Published var latest: IntentResult?
    @Published var connected = false

    private var task: URLSessionWebSocketTask?

    func connect() {
        task = URLSession.shared.webSocketTask(with: Config.wsURL)
        task?.resume()
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
                   let event = try? JSONDecoder().decode(WSEvent.self, from: data) {
                    Task { @MainActor in self.latest = event.data }
                }
                self.receive() // keep listening
            case .failure:
                Task { @MainActor in self.connected = false }
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        connected = false
    }
}
