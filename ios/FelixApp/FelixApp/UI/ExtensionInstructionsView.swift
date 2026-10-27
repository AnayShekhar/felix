import SwiftUI

/// A sheet explaining how to connect accounts, since a Chrome extension can't be
/// installed from the phone. Optionally highlights one service the agent just
/// said it needs (`highlightService`).
struct ExtensionInstructionsView: View {
    @Environment(\.dismiss) var dismiss
    var highlightService: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FelixSpacing.xl) {
                    Text("Connect your accounts")
                        .font(FelixTypography.displayMedium)
                        .foregroundColor(FelixColors.textPrimary)

                    if let service = highlightService, !service.isEmpty {
                        Text("Felix needs \(service.capitalized) to do that. Connect it below and try again.")
                            .font(FelixTypography.bodyMedium)
                            .foregroundColor(FelixColors.tintStrong)
                    }

                    Text("Felix uses a small Chrome extension on your computer to securely connect your accounts. Your phone tells Felix what to do — the extension is just how it gets access.")
                        .font(FelixTypography.bodyMedium)
                        .foregroundColor(FelixColors.textSecondary)

                    stepRow(number: 1, text: "On your computer, open Chrome and load the Felix extension")
                    stepRow(number: 2, text: "Sign in with the same account you used on your phone")
                    stepRow(number: 3, text: "Click Connect next to each account you want Felix to use")
                    stepRow(number: 4, text: "Come back here — it'll show up automatically")

                    Text("This extension isn't on the Chrome Web Store yet — ask for the install file directly.")
                        .font(FelixTypography.caption)
                        .foregroundColor(FelixColors.textSecondary)
                        .padding(.top, FelixSpacing.sm)
                }
                .padding(FelixSpacing.xl)
            }
            .background(FelixColors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: FelixSpacing.md) {
            Text("\(number)")
                .font(FelixTypography.titleSmall)
                .foregroundColor(FelixColors.onTint)
                .frame(width: 24, height: 24)
                .background(FelixColors.tint)
                .clipShape(Circle())
            Text(text)
                .font(FelixTypography.bodyMedium)
                .foregroundColor(FelixColors.textPrimary)
        }
    }
}
