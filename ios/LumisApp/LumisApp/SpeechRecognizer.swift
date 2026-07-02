import Foundation
import Combine
import Speech
import AVFoundation

/// "Hey Lumis" wake-word dictation with manual capture.
///
/// The mic stays open listening for the wake phrase. Saying "Hey Lumis" arms it:
/// the UI shows "Listening…" and live-transcribes the command that follows. When
/// you stop talking the transcript is held on screen so you can review it and tap
/// the capture button to send it — nothing is sent automatically. After capture
/// (`reset()`) it returns to waiting for the next "Hey Lumis".
@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Phase { case idle, waiting, hearing }

    @Published var phase: Phase = .idle
    @Published var command = ""          // command text spoken after the wake word
    @Published var authorized = false
    /// Which engine produced the current `command` — "Whisper", "Apple", or ""
    /// (nothing captured yet). Drives the small badge in the transcription card.
    @Published var transcriptionEngine = ""
    /// Live microphone input level, 0 (silence) → 1 (loud), sampled from the
    /// existing audio tap. Drives the Lumis mark's audio-reactive listening
    /// animation without opening a second AVAudioEngine on the same input.
    @Published var inputLevel: CGFloat = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // Groq Whisper command recording (Hotfix 1). While awake, the audio that
    // feeds Apple Speech is mirrored into `commandFile`; on silence it is sent to
    // Whisper to refine the command text (Apple stays as the live preview and the
    // silent fallback). Guarded by `recordLock` since the tap runs off-main.
    private var commandFile: AVAudioFile?
    private let recordLock = NSLock()
    private var tapFormat: AVAudioFormat?
    private var whisperGeneration = 0

    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var awake = false
    // Bumped on every (re)start; callbacks from a superseded task are ignored so
    // a cancellation error can't trigger a restart cascade that kills the engine.
    private var generation = 0

    // Fuzzy wake markers — Apple Speech frequently mishears "Lumis", so we accept
    // the common phonetic neighbours. `normalize` strips punctuation first, so
    // commas/apostrophes don't need their own entries.
    private let wakeMarkers = [
        "hey lumis", "hey loomis", "hey lumas", "hey lumus", "hey lumos",
        "hey luminous", "hey lewis", "hey louis", "hey loomiss",
        "hey felics", "hey phoenix",
        "a lumis", "okay lumis", "ok lumis",
    ]

    // Sample the input level every few buffers (the tap fires ~50×/s); publishing
    // on every buffer would needlessly thrash SwiftUI.
    private var levelSampleCounter = 0

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
            // The shared AVAudioSession is configured ONCE at ap p launch in
            // LumisApp.configureAudioSession() and never deactivated — that's the
            // Part 2 lag fix. Do NOT set the category/active state here.

            // Install the tap once; it feeds whatever request is current.
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            tapFormat = format
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.request?.append(buffer)
                // Mirror the same audio into the Whisper recording while awake.
                self.recordLock.lock()
                try? self.commandFile?.write(from: buffer)
                self.recordLock.unlock()
                // Sample the mic level for the listening animation (throttled).
                self.levelSampleCounter &+= 1
                if self.levelSampleCounter % 3 == 0 {
                    let level = Self.normalizedLevel(from: buffer)
                    Task { @MainActor [weak self] in self?.inputLevel = level }
                }
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
        transcriptionEngine = ""
        inputLevel = 0
        whisperGeneration &+= 1
        discardCommandRecording()
    }

    /// Called after a command is captured/sent: clear it and listen for the next
    /// "Hey Lumis". Restarting the task wipes the recognition buffer so the old
    /// wake phrase can't leak into the next command.
    func reset() {
        silenceTimer?.invalidate()
        awake = false
        command = ""
        transcriptionEngine = ""
        whisperGeneration &+= 1  // invalidate any in-flight Whisper result
        discardCommandRecording()
        if phase != .idle { phase = .waiting }
        restartTask()
    }

    /// Drop any in-progress command recording and delete its temp file.
    private func discardCommandRecording() {
        recordLock.lock()
        let url = commandFile?.url
        commandFile = nil
        recordLock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
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
            transcriptionEngine = ""
            startCommandRecording()
            armSilenceTimer()
        } else {
            // Re-extract after the wake word so we only ever show the command.
            command = commandAfterWake(in: norm) ?? command
            armSilenceTimer()
        }
    }

    // Silence after the command before we settle the transcript and fire Whisper.
    // Kept tight (Part 2) so Lumis responds quickly instead of waiting in dead air.
    private let silenceThreshold: TimeInterval = 1.0

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.holdForCapture() }
        }
    }

    /// User stopped talking. Keep the transcript on screen for manual capture and
    /// disarm the wake state so stray speech is ignored until the next "Hey Lumis".
    ///
    /// Deliberately does NOT restart the recognition task — restarting on every
    /// silence churns SFSpeechRecognizer into a state where it stops returning
    /// results after the first command. The task keeps running; `commandAfterWake`
    /// reads the text after the LAST "Hey Lumis", so a leftover earlier command in
    /// the buffer can't leak into the next one. The buffer is only cleared once,
    /// in `reset()` after a capture, and by the idle recycle timer.
    private func holdForCapture() {
        awake = false  // command stays published for the user to capture
        transcribeCommandWithWhisper()
    }

    // MARK: - Groq Whisper command capture (Hotfix 1)

    /// Begin mirroring the post-wake audio to a fresh temp wav file. No-op if the
    /// user hasn't configured a Groq key — we just keep Apple Speech.
    private func startCommandRecording() {
        guard WhisperTranscriber.isConfigured, let format = tapFormat else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumis-command-\(UUID().uuidString).wav")
        recordLock.lock()
        defer { recordLock.unlock() }
        commandFile = try? AVAudioFile(forWriting: url, settings: format.settings)
    }

    /// Close the recording and, if we captured anything, send it to Groq Whisper.
    /// On success replace `command` with the Whisper text; on any failure keep the
    /// Apple Speech transcript silently.
    private func transcribeCommandWithWhisper() {
        recordLock.lock()
        let file = commandFile
        commandFile = nil
        recordLock.unlock()
        guard let url = file?.url else { return }  // not recording (no key)

        whisperGeneration &+= 1
        let gen = whisperGeneration
        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await WhisperTranscriber.transcribe(fileURL: url)
                await MainActor.run { [weak self] in
                    guard let self, gen == self.whisperGeneration, !self.awake else { return }
                    // Strip any leaked wake phrase, then prefer the Whisper text.
                    let cleaned = self.stripWakePhrase(from: text)
                    if !cleaned.isEmpty {
                        self.command = cleaned
                        self.transcriptionEngine = "Whisper"
                    }
                }
            } catch {
                // Silent fallback: Apple Speech transcript already in `command`.
                await MainActor.run { [weak self] in
                    guard let self, gen == self.whisperGeneration else { return }
                    if !self.command.isEmpty { self.transcriptionEngine = "Apple" }
                }
            }
        }
    }

    /// Whisper transcribes the whole utterance including "Hey Lumis"; drop a
    /// leading wake phrase if present so only the command remains.
    private func stripWakePhrase(from text: String) -> String {
        let norm = normalize(text)
        if let after = commandAfterWake(in: norm), !after.isEmpty { return after }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    /// Average absolute amplitude of a buffer, normalized to roughly 0…1.
    /// Pure math — safe to call from the audio thread.
    private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += abs(data[i]) }
        let avg = sum / Float(frames)
        return CGFloat(min(avg * 20.0, 1.0))
    }

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
