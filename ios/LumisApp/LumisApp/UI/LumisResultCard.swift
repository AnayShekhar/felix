import SwiftUI

/// Slides up above the tab bar when Lumis completes an action. Auto-dismisses
/// after 8s unless the user interacts; swipe down to dismiss.
struct LumisResultCard: View {
    let result: ActionResult
    var onDismiss: () -> Void
    var onOpen: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    /// Show the "opens in your own browser" hint only until the user has seen it once.
    @AppStorage("lumis.hasSeenOpenHint") private var hasSeenOpenHint = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LumisColors.tintSoft).frame(width: 44, height: 44)
                Image(systemName: result.success ? result.actionType.symbol : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.success ? result.actionType.tint : LumisColors.destructive)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(LumisTypography.titleSmall)
                    .foregroundStyle(LumisColors.textPrimary)
                    .lineLimit(1)
                if !result.description.isEmpty {
                    Text(result.description)
                        .font(LumisTypography.bodySmall)
                        .foregroundStyle(LumisColors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)

            if result.deeplink != nil, let onOpen {
                VStack(alignment: .trailing, spacing: 3) {
                    Button("Open", action: onOpen)
                        .font(LumisTypography.captionMedium)
                        .foregroundStyle(LumisColors.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LumisColors.tintMid, in: Capsule())
                    if !hasSeenOpenHint {
                        Text("Opens in your own browser")
                            .font(LumisTypography.caption)
                            .foregroundStyle(LumisColors.textPrimary.opacity(0.4))
                            .onAppear { hasSeenOpenHint = true }
                    }
                }
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumisColors.textSecondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LumisColors.background.opacity(0.5)
            }
        )
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(alignment: .top) {
            Capsule().fill(LumisColors.textTertiary)
                .frame(width: 36, height: 4).padding(.top, 6)
        }
        .shadow(color: LumisColors.shadow, radius: 16, y: -2)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { if $0.translation.height > 60 { onDismiss() } else { dragOffset = 0 } }
        )
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title). \(result.description)")
    }
}
