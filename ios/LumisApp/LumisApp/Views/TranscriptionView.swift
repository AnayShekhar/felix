import SwiftUI

/// Phase 7 — live transcription shown below the orb while the user speaks.
/// SF Pro Regular 16pt, white 80%, max 2 lines, truncated from the left so the
/// most recent words stay visible. Fades in as words appear and fades out 1s
/// after the command is sent (driven by `visible`).
struct TranscriptionView: View {
    let text: String
    let visible: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(2)
            .truncationMode(.head)            // keep the most recent words
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .opacity(visible && !text.isEmpty ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: visible)
            .animation(.easeInOut(duration: 0.2), value: text)
    }
}
