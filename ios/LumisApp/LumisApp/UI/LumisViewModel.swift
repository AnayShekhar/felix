import Combine
import Foundation
import SwiftUI
import UIKit

/// The app's core runtime: owns the live WebSocket, the wake-word speech
/// recognizer, and the camera, and projects them into the home screen's three
/// states (dormant / listening / panel stack) plus the Past Chats archive.
///
/// Every request — voice, text, or camera — resolves into the same panel
/// stack: the agent's real-time events (agent_step / step_executed /
/// agent_done) translate directly into panels appearing, updating, and
/// completing. Lumis never speaks a reply; the response is entirely visual.
@MainActor
final class LumisViewModel: ObservableObject {
    /// The scribble's expression (idle vs. voice-reactive listening).
    @Published var lumisState: LumisState = .idle
    /// The stack being built (or re-read from Past Chats) right now.
    @Published var currentChat: ChatStack?
    @Published var isSending = false
    @Published var errorMessage: String?

    let ws = WebSocketClient()
    let speech = SpeechRecognizer()
    let camera = CameraManager()
    let pastChats = PastChatsStore()

    /// Set while the live camera is open: lets a spoken command include the
    /// current frame, so the camera path resolves into the same panel stack.
    var cameraFrameProvider: (() async -> UIImage?)?

    let sessionID = "ios-" + UUID().uuidString.prefix(8)
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    /// True when the open stack came from Past Chats (already archived —
    /// dismissing it or starting fresh must not archive it twice).
    private var viewingArchived = false
    /// True after the agent asked a clarifying question — the next message
    /// continues the same stack instead of starting a new one.
    private var awaitingReply = false
    /// Armed while a spoken command is being captured; cleared once sent.
    private var captureArmed = false
    private var settleTask: Task<Void, Never>?

    /// Watchdog for a run streaming over the WebSocket: when the last agent
    /// event for the visible stack was received, and the task that fails the
    /// stack honestly if the stream goes silent for too long.
    private var lastEventAt = Date()
    private var watchdogTask: Task<Void, Never>?
    /// How long the event stream may go quiet before the watchdog checks
    /// GET /latest and, failing that, concludes the stack. Browser steps can
    /// legitimately take tens of seconds, so this errs generous.
    private static let watchdogSilence: TimeInterval = 120

    init() { bind() }

    // MARK: - Lifecycle

    /// Whether the "Hey Lumis" wake word is enabled (Settings). Default on.
    static let wakeWordKey = "lumis.pref.wakeWord"
    var wakeWordEnabled: Bool { UserDefaults.standard.object(forKey: Self.wakeWordKey) as? Bool ?? true }

    /// Connect + (optionally) start listening. Safe to call repeatedly (idempotent).
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        // UI-screenshot hook: render a mid-flight panel stack.
        if ProcessInfo.processInfo.environment["LUMIS_UI_DEMO_STACK"] != nil {
            currentChat = ChatStack(
                request: "Find a good sushi place nearby and add it to my calendar",
                panels: [
                    Panel(title: "Researching", subtitle: "Found three well-reviewed spots near you", state: .complete),
                    Panel(title: "Reading", subtitle: "Checked tonight's opening hours", state: .complete),
                    Panel(title: "Scheduling", subtitle: "Adding dinner to your calendar"),
                ]
            )
            return
        }
        // UI-screenshot hook: skip auto-listen so no mic prompt covers the shot.
        if ProcessInfo.processInfo.environment["LUMIS_NO_MIC"] != nil {
            if let url = URL(string: LumisConfig.websocketURL) { ws.connect(to: url) }
            return
        }
        #endif
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
        // Scribble state: voice-reactive while the user is speaking.
        speech.$phase
            .sink { [weak self] phase in
                guard let self else { return }
                let hearing = phase == .hearing
                // Wake-word confirmation: a firm tap, matching the scribble's
                // visual surge — with no mic button, this pair IS the receipt
                // that Lumis heard you.
                if hearing { self.captureArmed = true; Haptics.medium() }
                let next: LumisState = hearing ? .listening : .idle
                if next != self.lumisState {
                    self.lumisState = next
                    UIAccessibility.post(notification: .announcement,
                                         argument: hearing ? "Lumis is listening" : "Lumis is ready")
                }
            }
            .store(in: &cancellables)

        // Auto-send: the moment the user finishes speaking, the command settles
        // and the request begins — no manual capture step, no transcript shown.
        speech.$command
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.armSettle() }
            .store(in: &cancellables)

        // Agent events → panels.
        ws.events
            .sink { [weak self] env in self?.handle(env) }
            .store(in: &cancellables)
    }

    /// Waits for the spoken command to settle (and, when Groq Whisper is
    /// configured, for its refined transcript) before sending. Restarted on
    /// every live-transcript change; only ever one in flight.
    private func armSettle() {
        guard captureArmed, !speech.command.isEmpty else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self, !Task.isCancelled else { return }
            if WhisperTranscriber.isConfigured {
                // Give Whisper a moment to replace the live preview text.
                for _ in 0..<20 where self.speech.transcriptionEngine.isEmpty {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                }
            }
            self.autoSendSpokenCommand()
        }
    }

    private func autoSendSpokenCommand() {
        guard captureArmed else { return }
        let text = speech.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        captureArmed = false
        Haptics.medium()
        let provider = cameraFrameProvider
        speech.reset()
        Task {
            let image = await provider?()
            self.send(image: image, text: text)
        }
    }

    // MARK: - Sending

    /// Send a request (any entry point). Continues the visible stack when the
    /// user is answering a question or replying inside a reopened past chat;
    /// otherwise archives it and starts fresh. The WebSocket events build the
    /// panels either way.
    func send(image: UIImage?, text: String) {
        var command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Photo-only capture: the camera shutter used to no-op because empty
        // text short-circuited here. Ground the agent on the image with a
        // clear default instruction when the user didn't speak.
        if command.isEmpty {
            guard image != nil else { return }
            command = "Look at this photo and help me with it."
        }

        if awaitingReply, var chat = currentChat, !viewingArchived {
            // Answering the agent's clarifying question: same stack continues.
            awaitingReply = false
            chat.panels.append(Panel(title: "Working",
                                     subtitle: "Picking up where we left off"))
            currentChat = chat
        } else if viewingArchived, var chat = currentChat {
            // Replying inside a reopened past chat: the new exchange appends
            // to that same stack, and the request carries the chat's context
            // so the agent treats it as a genuine follow-up.
            awaitingReply = false
            command = Self.continuation(of: chat, reply: command)
            chat.panels.append(Panel(title: "Working",
                                     subtitle: "Continuing this chat"))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                currentChat = chat
            }
        } else {
            archiveCurrent()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                currentChat = ChatStack(
                    request: command,
                    panels: [Panel(title: "Working", subtitle: "Getting started")]
                )
            }
        }
        viewingArchived = false

        isSending = true
        errorMessage = nil
        let stackID = currentChat?.id
        Task {
            do {
                let steps = try await APIClient.ingest(
                    image: image, voiceText: command,
                    sessionID: sessionID, baseURL: LumisConfig.backendURL
                )
                if steps.isEmpty {
                    // Normal path: the backend accepted the run and streams it
                    // over the WebSocket. The watchdog only steps in if that
                    // stream goes silent — it must NOT conclude the stack now.
                    startWatchdog(stackID: stackID)
                } else {
                    // Legacy backend that returned the finished steps inline.
                    reconcile(steps: steps, stackID: stackID)
                }
            } catch {
                let message = (error as NSError).localizedDescription
                failCurrent(with: message, stackID: stackID)
                errorMessage = message
                Haptics.error()
            }
            isSending = false
        }
    }

    /// Wraps a reply inside a reopened past chat with that chat's context —
    /// what was asked and how it concluded — so the agent handles it as a
    /// follow-up even though the original session's transcript is gone.
    private static func continuation(of chat: ChatStack, reply: String) -> String {
        var context = "This continues an earlier request: \"\(chat.request)\"."
        if let final = chat.panels.last(where: { $0.isFinal }), !final.body.isEmpty {
            context += " What happened then: \(final.body)"
        }
        return "\(context)\n\nThe user now says: \(reply)"
    }

    /// Dismiss the visible stack (user is done looking at it) — archives it,
    /// in full, into Past Chats.
    func dismissCurrentChat() {
        archiveCurrent()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            currentChat = nil
        }
    }

    /// Reopen a past chat exactly as it finished.
    func openPastChat(_ chat: ChatStack) {
        archiveCurrent()
        viewingArchived = true
        awaitingReply = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            currentChat = chat
        }
    }

    private func archiveCurrent() {
        guard let chat = currentChat else { return }
        awaitingReply = false
        guard !viewingArchived else { return }   // already in Past Chats
        var sealed = chat
        // A stack interrupted mid-run is archived honestly: unfinished panels
        // settle as incomplete rather than pretending to be done.
        for i in sealed.panels.indices where sealed.panels[i].state == .active {
            sealed.panels[i].state = .failed
            sealed.panels[i].subtitle = "Interrupted"
        }
        pastChats.archive(sealed)
    }

    // MARK: - Agent events → panels

    private func handle(_ env: WSEnvelope) {
        // Only this phone's own requests build panels.
        if let sid = env.session_id, sid != sessionID { return }
        lastEventAt = Date()   // any event for this session feeds the watchdog
        guard var chat = currentChat, !viewingArchived, !chat.isFinished else { return }

        switch env.event {
        case "agent_step":
            // The agent picked its next tool: the active panel's dynamic title
            // shifts to match what's actually happening now.
            let title = PanelWording.title(forTool: env.tool)
            let subtitle = env.message ?? PanelWording.subtitle(forTool: env.tool)
            if let i = chat.activeIndex {
                chat.panels[i].title = title
                chat.panels[i].subtitle = subtitle
            } else {
                chat.panels.append(Panel(title: title, subtitle: subtitle))
            }

        case "step_executed":
            guard let d = env.data else { return }
            // The terminal pseudo-tools are handled by their agent_* events.
            if d.tool == "lumis.finish" || d.tool == "lumis.ask" { return }
            let failed = d.status == "error"
            if let i = chat.activeIndex {
                chat.panels[i].state = failed ? .failed : .complete
                if let message = d.message, !message.isEmpty {
                    chat.panels[i].subtitle = message
                }
            }
            if !failed {
                // The agent is deciding what to do next — that thought is the
                // next panel, retitled when the next tool starts.
                chat.panels.append(Panel(title: "Thinking",
                                         subtitle: "Deciding what to do next"))
            }

        case "agent_question":
            let question = env.question ?? "Lumis needs a little more information."
            if let i = chat.activeIndex {
                chat.panels[i].title = "One quick question"
                chat.panels[i].subtitle = question
                chat.panels[i].state = .complete
            } else {
                chat.panels.append(Panel(title: "One quick question",
                                         subtitle: question, state: .complete))
            }
            awaitingReply = true
            Haptics.light()

        case "agent_done":
            if let i = chat.activeIndex { chat.panels[i].state = .complete }
            chat.panels.append(Panel(
                title: chat.request,
                subtitle: "",
                state: .complete,
                isFinal: true,
                body: env.summary ?? env.title ?? "Done.",
                link: env.url.flatMap(URL.init(string:))
            ))
            Haptics.success()

        case "agent_error":
            concludeWithFailure(&chat, message: env.message ?? "Something went wrong.")

        case "service_required":
            let pretty = (env.service ?? "an account").capitalized
            concludeWithFailure(
                &chat,
                message: env.message
                    ?? "Connect \(pretty) in the Lumis browser extension, then try again."
            )

        default:
            return   // agent_start / step_started / workflow_complete need no panel change
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentChat = chat
        }
    }

    private func concludeWithFailure(_ chat: inout ChatStack, message: String) {
        if let i = chat.activeIndex { chat.panels[i].state = .failed }
        chat.panels.append(Panel(title: chat.request, subtitle: "",
                                 state: .failed, isFinal: true, body: message))
        Haptics.error()
    }

    // MARK: - Watchdog (socket fallback)

    /// Fails the visible stack only if the agent's event stream goes silent
    /// for `watchdogSilence` — after first asking GET /latest whether the run
    /// actually concluded while the socket was down. Never fires while the
    /// agent is streaming or waiting on the user's answer.
    private func startWatchdog(stackID: UUID?) {
        watchdogTask?.cancel()
        lastEventAt = Date()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let chat = self.currentChat, chat.id == stackID,
                      !chat.isFinished else { return }         // done or dismissed
                if self.awaitingReply { continue }             // user is answering
                guard Date().timeIntervalSince(self.lastEventAt) > Self.watchdogSilence
                else { continue }

                // Silent too long — did the run finish while the socket was out?
                if let latest = try? await APIClient.latest(baseURL: LumisConfig.backendURL),
                   latest.session_id == self.sessionID, latest.event == "agent_done" {
                    self.handle(latest)
                } else {
                    self.failCurrent(
                        with: "Lumis stopped responding. Check your connection and try again.",
                        stackID: stackID)
                }
                return
            }
        }
    }

    /// Conclude the stack from an inline /ingest step list (legacy backends
    /// that ran the workflow synchronously).
    private func reconcile(steps: [StepResult], stackID: UUID?) {
        guard var chat = currentChat, chat.id == stackID,
              !chat.isFinished, !awaitingReply else { return }
        guard let last = steps.last else { return }
        let failed = last.status == "error"
        if let i = chat.activeIndex { chat.panels[i].state = failed ? .failed : .complete }
        chat.panels.append(Panel(
            title: chat.request,
            subtitle: "",
            state: failed ? .failed : .complete,
            isFinal: true,
            body: last.summary ?? last.message ?? (failed ? "Something went wrong." : "Done."),
            link: last.url.flatMap(URL.init(string:))
        ))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { currentChat = chat }
    }

    private func failCurrent(with message: String, stackID: UUID?) {
        guard var chat = currentChat, chat.id == stackID, !chat.isFinished else { return }
        concludeWithFailure(&chat, message: message)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { currentChat = chat }
    }
}
