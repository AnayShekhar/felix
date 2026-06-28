import SwiftUI

/// Persistent, non-dismissible banner shown on Home when the linked Mac is
/// offline. Powder Blue background, Carbon Black text, manual "Reconnect".
struct MacOfflineBanner: View {
    var onReconnect: () -> Void
    @State private var spinning = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(LumisColors.carbonBlack)
                .accessibilityHidden(true)
            Text("Your Mac is offline — actions won't run until it reconnects")
                .font(LumisTypography.bodySmall)
                .foregroundStyle(LumisColors.carbonBlack)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                spinning = true
                onReconnect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { spinning = false }
            } label: {
                Text("Reconnect")
                    .font(LumisTypography.captionMedium)
                    .foregroundStyle(LumisColors.carbonBlack)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LumisColors.parchment.opacity(0.6), in: Capsule())
            }
            .accessibilityLabel("Reconnect to Mac")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(LumisColors.powderBlue)
        .accessibilityElement(children: .combine)
    }
}
