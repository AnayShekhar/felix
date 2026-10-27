import SwiftUI

/// Shown in Settings when the account has zero connected services — nudges the
/// user toward the Felix Chrome extension on their computer.
struct ConnectServicesEmptyState: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: FelixSpacing.md) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.largeTitle.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(FelixColors.textSecondary)

            Text("No accounts connected yet")
                .font(FelixTypography.titleSmall)
                .foregroundColor(FelixColors.textPrimary)

            Text("Install the Felix Chrome extension on your computer to connect Gmail, Sheets, Notion, and more.")
                .font(FelixTypography.bodySmall)
                .foregroundColor(FelixColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onGetStarted) {
                Text("Get started")
                    .font(FelixTypography.titleSmall)
                    .foregroundColor(FelixColors.background)
                    .padding(.horizontal, FelixSpacing.screenMargin)
                    .padding(.vertical, 10)
                    .background(FelixColors.textPrimary, in: Capsule())
            }
            .buttonStyle(.felixPress)
            .padding(.top, FelixSpacing.xs)
        }
        .padding(FelixSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
