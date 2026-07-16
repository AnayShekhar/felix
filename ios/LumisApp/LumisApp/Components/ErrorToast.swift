import SwiftUI

/// Slide-up error toast. It names the failure, offers a 44pt dismiss target,
/// and auto-dismisses after four seconds without ever hiding an API error in
/// the console.
struct ErrorToast: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body)
                .foregroundStyle(LumisColors.destructive)
            Text(message)
                .font(LumisTypography.bodySmall)
                .foregroundStyle(LumisColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LumisColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.lumisPress)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.vertical, LumisSpacing.sm)
        .padding(.leading, LumisSpacing.md)
        .padding(.trailing, LumisSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumisColors.surfaceProminent, in: LumisRadius.rect(LumisRadius.lg))
        .lumisGlass(in: LumisRadius.rect(LumisRadius.lg))
        .padding(.horizontal, LumisSpacing.screenMargin)
        .shadow(color: LumisColors.shadow, radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            onDismiss()
        }
        .accessibilityLabel("Error: \(message)")
    }
}
