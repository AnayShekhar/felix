import Foundation
import Combine
import Speech
import AVFoundation

/// "Hey Felix" wake-word dictation with manual capture.
///
/// The mic stays open listening for the wake phrase. Saying "Hey Felix" arms it:
/// the UI shows "Listening…" and live-transcribes the command that follows. When
/// you stop talking the transcript is held on screen so you can review it and tap
/// the capture button to send it — nothing is sent automatically. After capture
/// (`reset()`) it returns to waiting for the next "Hey Felix".
@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Phase { case idle, waiting, hearing }

    @Published var phase: Phase = .idle
    @Published var command = ""          // command text spoken after the wake word
    @Published var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var awake = false
    // Bumped on every (re)start; callbacks from a superseded task are ignored so
    // a cancellation error can't trigger a restart cascade that kills the engine.
    private var generation = 0

    private let wakeMarkers = [
        "hey felix", "hey, felix", "hey felics", "hey felux", "hey feelix",
        "hey phoenix", "a felix", "hey felicks",
    ]

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorized = (status == .authorized)
            }
        }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    // MARK: - Lifecycle

    func startListening() {
        guard engine.isRunning == false else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Install the tap once; it feeds whatever request is current.
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            engine.prepare()
            try engine.start()

            phase = .waiting
            beginTask()
        } catch {
            phase = .idle
        }
    }

    func stopListening() {
        restartTimer?.invalidate()
        silenceTimer?.invalidate()
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        awake = false
        phase = .idle
        command = ""
    }

    /// Called after a command is captured/sent: clear it and listen for the next
    /// "Hey Felix". Restarting the task wipes the recognition buffer so the old
    /// wake phrase can't leak into the next command.
    func reset() {
        silenceTimer?.invalidate()
        awake = false
        command = ""
        if phase != .idle { phase = .waiting }
        restartTask()
    }

    // MARK: - Recognition session

    private func beginTask() {
        generation &+= 1
        let gen = generation

        // Cancel the previous task; its (cancellation) callbacks will be stale.
        task?.cancel()
        request?.endAudio()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }  // ignore stale task
                if let text { self.process(text) }
                // Only a live task's error should recycle, and only while idle.
                if failed, !self.awake { self.restartTask() }
            }
        }

        // SFSpeech tasks cap at ~1 minute — recycle proactively while idle.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self, !self.awake else { return }
                self.restartTask()
            }
        }
    }

    private func restartTask() {
        guard engine.isRunning else { return }
        beginTask()
    }

    // MARK: - Transcript processing

    private func process(_ raw: String) {
        let norm = normalize(raw)

        if !awake {
            guard let after = commandAfterWake(in: norm) else { return }
            awake = true
            phase = .hearing
            command = after
            armSilenceTimer()
        } else {
            // Re-extract after the wake word so we only ever show the command.
            command = commandAfterWake(in: norm) ?? command
            armSilenceTimer()
        }
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.holdForCapture() }
        }
    }

    /// User stopped talking. Keep the transcript on screen for manual capture and
    /// disarm the wake state so stray speech is ignored until the next "Hey Felix".
    ///
    /// Deliberately does NOT restart the recognition task — restarting on every
    /// silence churns SFSpeechRecognizer into a state where it stops returning
    /// results after the first command. The task keeps running; `commandAfterWake`
    /// reads the text after the LAST "Hey Felix", so a leftover earlier command in
    /// the buffer can't leak into the next one. The buffer is only cleared once,
    /// in `reset()` after a capture, and by the idle recycle timer.
    private func holdForCapture() {
        awake = false  // command stays published for the user to capture
    }

    // MARK: - Helpers

    private func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let stripped = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(stripped))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Text following the LAST wake phrase in the transcript, or nil if none.
    private func commandAfterWake(in norm: String) -> String? {
        var found: String?
        for marker in wakeMarkers {
            var searchStart = norm.startIndex
            while let r = norm.range(of: marker, range: searchStart..<norm.endIndex) {
                found = String(norm[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                searchStart = r.upperBound
            }
        }
        return found
    }
}
