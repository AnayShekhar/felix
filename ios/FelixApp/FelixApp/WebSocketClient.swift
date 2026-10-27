import Foundation
import Combine
import UIKit

/// Live event stream from the backend. Decodes every envelope and forwards it
/// on `events` — the view model translates agent_* events into the panel
/// stack. Felix never speaks results aloud; the entire response is visual,
/// through panels, so there is no TTS here.
@MainActor
final class WebSocketClient: ObservableObject {
    @Published var connected = false

    /// Every decoded envelope, in arrival order.
    let events = PassthroughSubject<WSEnvelope, Never>()

    private var task: URLSessionWebSocketTask?
    private var wantConnection = false
    private var currentURL: URL?
    /// Reconnect backoff: 2s doubling to a 30s cap, reset on a live connection —
    /// never a tight retry loop against a struggling backend.
    private var reconnectDelay: TimeInterval = 2

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
                    self.reconnectDelay = 2   // healthy again — reset backoff
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
        // iOS-native action: open the URL scheme on the phone directly.
        if env.event == "step_executed", env.data?.status == "ios_action" {
            openIOSAction(primary: env.data?.url, fallback: env.data?.fallback_url)
        }
        events.send(env)
    }

    /// Open an ios_action URL scheme on the phone. If the primary scheme can't
    /// be opened, falls back to the secondary scheme when one was provided.
    private func openIOSAction(primary: String?, fallback: String?) {
        guard let primary, let url = URL(string: primary) else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success, let fallback, let alt = URL(string: fallback) else { return }
            Task { @MainActor in UIApplication.shared.open(alt) }
        }
    }

    private func handleDisconnect() {
        connected = false
        task = nil
        guard wantConnection, let url = currentURL else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
