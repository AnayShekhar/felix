import Foundation
import Combine
import AVFoundation
import UIKit

@MainActor
final class WebSocketClient: ObservableObject {
    @Published var latest: StepResult?
    @Published var connected = false
    @Published var working = false
    @Published var activeTask: TaskState?   // live background task (Phase 5)
    // Set when the agent asks for an account the user hasn't connected yet.
    @Published var requiredService: String?

    // Lumis speaks results aloud when enabled (Fix 7). Default on; persisted.
    @Published var voiceEnabled: Bool =
        UserDefaults.standard.object(forKey: "lumis.voiceEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceEnabled, forKey: "lumis.voiceEnabled") }
    }

    /// True while Lumis is speaking a result aloud — drives the orb SPEAKING
    /// state (Phase 4). Set by the speech monitor on the main thread.
    @Published var speaking = false
    /// Called on each TTS word boundary so the orb can pulse in time (Phase 4).
    var onWordBoundary: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Delegate bridge for TTS start/word/end → `speaking` + `onWordBoundary`.
    private lazy var speechMonitor = SpeechMonitor(
        onStart: { [weak self] in self?.speaking = true },
        onWord: { [weak self] in self?.onWordBoundary?() },
        onEnd: { [weak self] in self?.speaking = false }
    )
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
        switch env.event {
        case "step_started":
            working = true
        case "step_executed":
            if let d = env.data {
                latest = StepResult(tool: d.tool, status: d.status, message: d.message,
                                    title: d.title, detail: d.detail, url: d.url,
                                    speak: d.speak, summary: d.summary)
                speakIfEnabled(d.speak)
                // iOS native action (Phase 5): open the URL scheme on the phone.
                // The result toast still shows via `latest` (message field).
                if d.status == "ios_action" {
                    openIOSAction(primary: d.url, fallback: d.fallback_url)
                }
            }
        case "service_required":
            // The requested tool needs an account the user hasn't connected.
            working = false
            let service = env.service ?? ""
            requiredService = service
            let pretty = service.isEmpty ? "an account" : service.capitalized
            let msg = env.message ?? "Connect \(pretty) in the Lumis browser extension to use that."
            latest = StepResult(tool: "lumis.connect", status: "error", message: msg,
                                title: "Connect \(pretty)", detail: nil, url: nil,
                                speak: env.speak ?? msg, summary: nil)
            speakIfEnabled(env.speak ?? msg)
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

    /// Speak a result aloud via AVSpeechSynthesizer when voice is enabled (Fix 7).
    /// Open an ios_action URL scheme on the phone (Phase 5). Runs on the main
    /// thread (this type is @MainActor). If the primary scheme can't be opened,
    /// falls back to the secondary scheme when one was provided.
    private func openIOSAction(primary: String?, fallback: String?) {
        guard let primary, let url = URL(string: primary) else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success, let fallback, let alt = URL(string: fallback) else { return }
            Task { @MainActor in UIApplication.shared.open(alt) }
        }
    }

    private func speakIfEnabled(_ speak: String?) {
        guard voiceEnabled, let speak, !speak.isEmpty else { return }
        synthesizer.delegate = speechMonitor   // idempotent; enables orb pulses
        let utterance = AVSpeechUtterance(string: speak)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
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
