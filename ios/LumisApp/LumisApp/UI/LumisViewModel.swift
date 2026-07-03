import Combine
import Foundation
import SwiftUI
import UIKit

/// The app's core runtime: owns the live WebSocket, the wake-word speech
/// recognizer, and the camera, and projects them into a single `lumisState`
/// plus the transcript / response / last result that the UI renders.
@MainActor
final class LumisViewModel: ObservableObject {
    @Published var lumisState: LumisState = .idle
    @Published var transcript = ""
    @Published var responseText = ""
    @Published var lastResult: ActionResult?
    @Published var isSending = false
    @Published var errorMessage: String?

    let ws = WebSocketClient()
    let speech = SpeechRecognizer()
    let camera = CameraManager()

    let sessionID = "ios-" + UUID().uuidString.prefix(8)
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init() { bind() }

    // MARK: - Lifecycle

    /// Whether the "Hey Lumis" wake word is enabled (Settings). Default on.
    static let wakeWordKey = "lumis.pref.wakeWord"
    var wakeWordEnabled: Bool { UserDefaults.standard.object(forKey: Self.wakeWordKey) as? Bool ?? true }

    /// Connect + (optionally) start listening. Safe to call repeatedly (idempotent).
    func start() {
        guard !started else { return }
        started = true
        // The socket is scoped to this account (?token=…) so the backend only
        // streams this user's events to it.
        var comps = URLComponents(string: LumisConfig.websocketURL)
        if let token = KeychainManager.token {
            comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        if let url = comps?.url { ws.connect(to: url) }
        if wakeWordEnabled {
            speech.requestPermission()
            speech.startListening()
        }
    }

    /// React to the Settings wake-word toggle immediately.
    func setWakeWord(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.wakeWordKey)
        if on {
            speech.requestPermission()
            speech.startListening()
        } else {
            speech.stopListening()
        }
    }

    func stop() {
        started = false
        speech.stopListening()
        ws.disconnect()
    }

    // MARK: - Binding

    private func bind() {
        // Derive lumisState from the underlying engines.
        ws.$working.sink { [weak self] _ in self?.recomputeState() }.store(in: &cancellables)
        ws.$speaking.sink { [weak self] _ in self?.recomputeState() }.store(in: &cancellables)
        speech.$phase.sink { [weak self] _ in self?.recomputeState() }.store(in: &cancellables)

        // Live transcript while the user speaks.
        speech.$command
            .receive(on: RunLoop.main)
            .sink { [weak self] cmd in self?.transcript = cmd }
            .store(in: &cancellables)

        // Result + spoken response.
        ws.$latest
            .compactMap { $0 }
            .sink { [weak self] step in
                guard let self else { return }
                let result = ActionResult(step: step)
                self.lastResult = result
                self.responseText = step.speak ?? step.message ?? ""
                if !result.success { Haptics.error() } else { Haptics.success() }
            }
            .store(in: &cancellables)
    }

    private func recomputeState() {
        let next: LumisState
        if ws.working { next = .thinking }
        else if ws.speaking { next = .speaking }
        else if speech.phase == .hearing { next = .listening }
        else { next = .idle }
        if next != lumisState {
            lumisState = next
            if next == .listening { Haptics.light() }
            UIAccessibility.post(notification: .announcement, argument: accessibilityState(next))
        }
    }

    private func accessibilityState(_ s: LumisState) -> String {
        switch s {
        case .idle: return "Lumis is ready"
        case .listening: return "Lumis is listening"
        case .thinking: return "Lumis is thinking"
        case .speaking: return "Lumis is speaking"
        }
    }

    // MARK: - Sending

    /// Send the current spoken command (Home capture button), no image.
    func sendSpokenCommand() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(image: nil, text: text)
        speech.reset()
    }

    /// Send an image + text (Camera screen).
    func send(image: UIImage?, text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        Task {
            do {
                let steps = try await APIClient.ingest(
                    image: image, voiceText: command,
                    sessionID: sessionID, baseURL: LumisConfig.backendURL
                )
                if let last = steps.last { lastResult = ActionResult(step: last) }
            } catch {
                errorMessage = "Couldn't reach Lumis. Check your connection."
                Haptics.error()
            }
            isSending = false
        }
    }

    // MARK: - Status dot helpers

    var connectionPulse: Bool { ws.connected }
}
