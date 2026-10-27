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
                .foregroundStyle(FelixColors.destructive)
            Text(message)
                .font(FelixTypography.bodySmall)
                .foregroundStyle(FelixColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FelixColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.felixPress)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.vertical, FelixSpacing.sm)
        .padding(.leading, FelixSpacing.md)
        .padding(.trailing, FelixSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FelixColors.surfaceProminent, in: FelixRadius.rect(FelixRadius.lg))
        .felixGlass(in: FelixRadius.rect(FelixRadius.lg))
        .padding(.horizontal, FelixSpacing.screenMargin)
        .shadow(color: FelixColors.shadow, radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            onDismiss()
        }
        .accessibilityLabel("Error: \(message)")
    }
}
