import Foundation
import AVFoundation
import Combine

/// Publishes a normalized 0…1 voice amplitude used to drive the orb during the
/// LISTENING and SPEAKING states.
///
/// SpeechRecognizer already owns the shared `AVAudioSession` (play-and-record)
/// and its own engine tap — we must never touch that file. To read the mic level
/// without interfering, this uses a lightweight metering-only `AVAudioRecorder`
/// pointed at /dev/null and polls `averagePower` on a 30 Hz timer. If the meter
/// can't start (session busy), amplitude simply stays at 0 and the orb falls back
/// to its idle motion — no crash, no silent console-only failure.
@MainActor
final class VoiceAmplitudeTracker: ObservableObject {
    /// Smoothed amplitude, 0.0 (silent) … 1.0 (loud).
    @Published private(set) var amplitude: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// dBFS range mapped to 0…1. Below `minDb` reads as silence.
    private let minDb: Float = -55
    private let maxDb: Float = -10
    private let smoothing: Float = 0.25   // exponential moving average factor

    var lastError: String?

    func start() {
        guard recorder == nil else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let rec = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"),
                                          settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else { lastError = "Mic metering unavailable."; return }
            recorder = rec
            startTimer()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        amplitude = 0
    }

    private func startTimer() {
        timer?.invalidate()
        // 30 Hz — smooth enough for animation, light on the battery.
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer = t
    }

    private func sample() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)   // dBFS, ~ -160…0
        let clamped = min(max(db, minDb), maxDb)
        let normalized = (clamped - minDb) / (maxDb - minDb)
        // Exponential moving average so the orb doesn't jitter frame-to-frame.
        amplitude += (normalized - amplitude) * smoothing
    }
}
