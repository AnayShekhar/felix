import Foundation
import AVFoundation

/// Bridges `AVSpeechSynthesizerDelegate` callbacks into plain closures so the
/// orb can pulse with Felix's TTS (Phase 4 SPEAKING). `AVSpeechSynthesizerDelegate`
/// requires an `NSObject`, which `WebSocketClient` (an `ObservableObject`) is not —
/// so this lightweight monitor is set as the synthesizer's delegate instead.
///
/// All callbacks are marshalled to the main thread; the consumers update
/// `@MainActor` UI state and the orb animator.
final class SpeechMonitor: NSObject, AVSpeechSynthesizerDelegate {
    private let onStart: () -> Void
    private let onWord: () -> Void
    private let onEnd: () -> Void

    init(onStart: @escaping () -> Void,
         onWord: @escaping () -> Void,
         onEnd: @escaping () -> Void) {
        self.onStart = onStart
        self.onWord = onWord
        self.onEnd = onEnd
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async(execute: onStart)
    }

    /// Fired just before each word — drives a small per-word orb pulse.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        DispatchQueue.main.async(execute: onWord)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async(execute: onEnd)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async(execute: onEnd)
    }
}
