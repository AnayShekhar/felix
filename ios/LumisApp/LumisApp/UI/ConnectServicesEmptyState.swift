import SwiftUI

/// Shown in Settings when the account has zero connected services — nudges the
/// user toward the Lumis Chrome extension on their computer.
struct ConnectServicesEmptyState: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 32))
                .foregroundColor(LumisColors.tint)

            Text("No accounts connected yet")
                .font(LumisTypography.titleSmall)
                .foregroundColor(LumisColors.textPrimary)

            Text("Install the Lumis Chrome extension on your computer to connect Gmail, Sheets, Notion, and more.")
                .font(LumisTypography.bodySmall)
                .foregroundColor(LumisColors.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onGetStarted) {
                Text("How to connect")
                    .font(LumisTypography.bodyMedium)
                    .foregroundColor(LumisColors.background)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(LumisColors.textPrimary)
                    .cornerRadius(20)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
