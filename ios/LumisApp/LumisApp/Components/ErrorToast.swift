import SwiftUI

/// Slide-up error toast (not an alert). Red left border, Carbon Black text,
/// auto-dismisses after 4s. Sits above the tab bar / screen bottom.
struct ErrorToast: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(LumisColors.destructive)
                .frame(width: 3)
                .clipShape(Capsule())
            Text(message)
                .font(LumisTypography.bodySmall)
                .foregroundStyle(LumisColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LumisRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: LumisRadius.md).stroke(LumisColors.divider, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .shadow(color: LumisColors.shadow, radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            onDismiss()
        }
        .onTapGesture(perform: onDismiss)
        .accessibilityLabel("Error: \(message)")
    }
}
