import SwiftUI

/// Shown in Settings when the account has zero connected services — nudges the
/// user toward the Lumis Chrome extension on their computer.
struct ConnectServicesEmptyState: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: LumisSpacing.md) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.largeTitle.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(LumisColors.textSecondary)

            Text("No accounts connected yet")
                .font(LumisTypography.titleSmall)
                .foregroundColor(LumisColors.textPrimary)

            Text("Install the Lumis Chrome extension on your computer to connect Gmail, Sheets, Notion, and more.")
                .font(LumisTypography.bodySmall)
                .foregroundColor(LumisColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onGetStarted) {
                Text("Get started")
                    .font(LumisTypography.titleSmall)
                    .foregroundColor(LumisColors.background)
                    .padding(.horizontal, LumisSpacing.screenMargin)
                    .padding(.vertical, 10)
                    .background(LumisColors.textPrimary, in: Capsule())
            }
            .buttonStyle(.lumisPress)
            .padding(.top, LumisSpacing.xs)
        }
        .padding(LumisSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
