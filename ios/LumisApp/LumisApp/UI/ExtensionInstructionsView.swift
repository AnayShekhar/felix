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
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connect your accounts")
                        .font(LumisTypography.displayMedium)
                        .foregroundColor(LumisColors.carbonBlack)

                    if let service = highlightService, !service.isEmpty {
                        Text("Lumis needs \(service.capitalized) to do that. Connect it below and try again.")
                            .font(LumisTypography.bodyMedium)
                            .foregroundColor(LumisColors.powderBlue)
                    }

                    Text("Lumis uses a small Chrome extension on your computer to securely connect your accounts. Your phone tells Lumis what to do — the extension is just how it gets access.")
                        .font(LumisTypography.bodyMedium)
                        .foregroundColor(LumisColors.carbonBlack.opacity(0.7))

                    stepRow(number: 1, text: "On your computer, open Chrome and load the Lumis extension")
                    stepRow(number: 2, text: "Sign in with the same account you used on your phone")
                    stepRow(number: 3, text: "Click Connect next to each account you want Lumis to use")
                    stepRow(number: 4, text: "Come back here — it'll show up automatically")

                    Text("This extension isn't on the Chrome Web Store yet — ask for the install file directly.")
                        .font(LumisTypography.caption)
                        .foregroundColor(LumisColors.carbonBlack.opacity(0.5))
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background(LumisColors.parchment)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(LumisTypography.bodyMedium.bold())
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(LumisColors.powderBlue)
                .clipShape(Circle())
            Text(text)
                .font(LumisTypography.bodyMedium)
                .foregroundColor(LumisColors.carbonBlack)
        }
    }
}
