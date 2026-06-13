import Foundation
import Combine
import Speech
import AVFoundation

/// Continuous "Hey Felix" wake-word listener.
///
/// Keeps the mic open, watches the transcript for the wake phrase, then captures
/// the spoken command that follows. When the user stops talking (short silence),
/// it finalizes and fires `onCommand`, then resets to listen for the next wake.
@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Phase { case idle, listening, awake }

    @Published var phase: Phase = .idle
    @Published var command = ""          // live command text after the wake word
    @Published var authorized = false

    /// Called with the finalized command (never empty) after the wake word.
    var onCommand: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var awake = false
    private var pendingCommand = ""

    private let wakeMarkers = ["hey felix", "hey, felix", "a felix", "hey felics", "hey phoenix"]

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

            phase = .listening
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

    // MARK: - Recognition session

    private func beginTask() {
        request?.endAudio()
        task?.cancel()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in self.process(result.bestTranscription.formattedString) }
            }
            if error != nil {
                Task { @MainActor in self.restartTask() }
            }
        }

        // SFSpeech tasks cap at ~1 minute — recycle proactively while idle.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in
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
            phase = .awake
            pendingCommand = after
            command = after
            armSilenceTimer()
        } else {
            // Re-extract after the wake word so we always show just the command.
            let after = commandAfterWake(in: norm) ?? norm
            pendingCommand = after
            command = after
            armSilenceTimer()
        }
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finalizeCommand() }
        }
    }

    private func finalizeCommand() {
        let final = pendingCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        awake = false
        pendingCommand = ""
        command = ""
        phase = .listening

        if !final.isEmpty {
            onCommand?(final)
        }
        // Clear the transcript for the next wake word.
        restartTask()
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

    /// Returns the command text that follows the wake phrase, or nil if no wake.
    private func commandAfterWake(in norm: String) -> String? {
        for marker in wakeMarkers {
            if let r = norm.range(of: marker) {
                return String(norm[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
