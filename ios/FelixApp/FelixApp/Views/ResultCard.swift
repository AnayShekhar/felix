import SwiftUI

/// Phase 8 — result presentation.
///
/// `ResultCard` is the small glass card that slides up from the bottom when Felix
/// finishes an action. Content tools (calendar, email, research, contacts, notes,
/// spreadsheet) instead use `ContentResultSheet`, a full bottom sheet with a
/// scrollable summary. Presentation timing (auto-dismiss, hold-during-TTS) is
/// owned by ContentView; these views just render and report taps.
enum ResultPresentation {
    /// Tools whose results warrant the full summary sheet rather than the card.
    static let contentTools: Set<String> = [
        "calendar.read_today", "calendar.read_week", "calendar.create_event",
        "reminders.read_list", "contacts.find", "system.get_battery",
        "web.research", "screen.capture_and_describe",
        "gmail.read_inbox", "gmail.read_email", "notes.list_notes",
        "numbers.read_sheet",
    ]

    static func usesSheet(_ result: StepResult) -> Bool {
        guard let tool = result.tool else { return false }
        guard let summary = result.summary, !summary.isEmpty else { return false }
        return contentTools.contains(tool)
    }
}

// MARK: - Small result card

struct ResultCard: View {
    let result: StepResult
    let onDismiss: () -> Void

    private var failed: Bool { result.status == "error" }
    private var meta: (label: String, symbol: String) { toolMeta(result.tool) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Tool icon in a Moonstone-tinted circle.
                Circle()
                    .fill(failed ? FelixColor.error : FelixColor.orbPrimary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: failed ? "exclamationmark.triangle.fill" : meta.symbol)
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(.black)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text((failed ? "Couldn’t complete" : meta.label).uppercased())
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(result.title ?? meta.label)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let message = result.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }

            if let urlString = result.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Open")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FelixColor.orbPrimary,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DarkBlurView().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(FelixColor.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }   // tap anywhere dismisses early
    }
}

// MARK: - Content tool bottom sheet

struct ContentResultSheet: View {
    let result: StepResult
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var meta: (label: String, symbol: String) { toolMeta(result.tool) }
    private var text: String { result.summary ?? result.message ?? "" }

    /// Prose reads better in SF Pro; structured data in mono.
    private var monospaced: Bool {
        switch result.tool {
        case "web.research", "screen.capture_and_describe": return false
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Circle()
                    .fill(FelixColor.orbPrimary)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: meta.symbol)
                            .font(.system(size: 23, weight: .heavy))
                            .foregroundStyle(.black)
                    )
                Text(result.title ?? meta.label)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 22).padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.12))

            ScrollView {
                Text(text)
                    .font(monospaced ? .system(size: 15, design: .monospaced)
                                     : .system(size: 15))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(20)
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { copied = true }
                } label: {
                    sheetButtonLabel(copied ? "Copied!" : "Copy",
                                     symbol: copied ? "checkmark" : "doc.on.doc.fill",
                                     tint: FelixColor.orbPrimary,
                                     background: FelixColor.orbPrimary.opacity(0.14))
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    sheetButtonLabel("Dismiss", symbol: nil,
                                     tint: .white.opacity(0.85),
                                     background: .white.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FelixColor.background)
        .preferredColorScheme(.dark)
    }

    private func sheetButtonLabel(_ title: String, symbol: String?,
                                  tint: Color, background: Color) -> some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.system(size: 16, weight: .heavy))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
