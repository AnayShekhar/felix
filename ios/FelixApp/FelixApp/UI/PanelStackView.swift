import SwiftUI

/// The vertical stack of live status panels for one request. Panels append
/// downward, most recent at the bottom; the active panel is unmistakably the
/// focus while completed panels above it recede but stay readable — the whole
/// trail of what happened, like a timeline.
struct PanelStackView: View {
    let chat: ChatStack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil while the stack is still running (no dismissal mid-run).
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: FelixSpacing.md) {
                    ForEach(chat.panels) { panel in
                        Group {
                            if panel.isFinal {
                                FinalPanelView(panel: panel)
                            } else {
                                StepPanelView(panel: panel)
                            }
                        }
                        .id(panel.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96, anchor: .bottom)),
                            removal: .opacity
                        ))
                    }

                    if chat.isFinished, let onDismiss {
                        Button {
                            Haptics.light()
                            onDismiss()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(FelixTypography.titleSmall)
                                .foregroundStyle(FelixColors.textSecondary)
                                .padding(.horizontal, FelixSpacing.xl)
                                .frame(height: 44)
                        }
                        .buttonStyle(.felixPress)
                        .felixGlass(in: Capsule(), interactive: true)
                        .padding(.top, FelixSpacing.sm)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityLabel("Dismiss this request")
                    }

                    // Bottom anchor so new panels scroll into view.
                    Color.clear.frame(height: 1).id("stack-bottom")
                }
                .padding(.horizontal, FelixSpacing.screenMargin)
                .padding(.top, FelixSpacing.md)
                .padding(.bottom, 96)   // clears the input bar
            }
            .scrollIndicators(.hidden)
            .onChange(of: chat.panels.count) { _, _ in
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo("stack-bottom", anchor: .bottom)
                }
            }
        }
    }
}

/// A working panel: dynamic status title + one plain-language line. Active
/// panels are large and bright; completed ones settle back with a checkmark.
private struct StepPanelView: View {
    let panel: Panel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { panel.state == .active }

    var body: some View {
        HStack(alignment: .top, spacing: FelixSpacing.md) {
            statusMark
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: FelixSpacing.xs) {
                // The dynamic status word ("Working," "Researching," …) —
                // crossfades between values instead of snapping.
                Text(panel.title)
                    .font(isActive ? FelixTypography.titleLarge : FelixTypography.titleSmall)
                    .foregroundStyle(isActive ? FelixColors.tintStrong : FelixColors.textPrimary)
                    .contentTransition(.opacity)

                if !panel.subtitle.isEmpty {
                    Text(panel.subtitle)
                        .font(isActive ? FelixTypography.bodyMedium : FelixTypography.bodySmall)
                        .foregroundStyle(FelixColors.textSecondary)
                        .lineLimit(isActive ? 3 : 2)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(isActive ? FelixSpacing.xl : FelixSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The selected step receives the one quiet slate-blue wash. Completed
        // actions remain neutral and readable, rather than shrinking into a
        // decorative stack of cards.
        .background(
            FelixRadius.rect(FelixRadius.card)
                .fill(isActive ? FelixColors.tintWash : FelixColors.surface)
        )
        .felixGlass(in: FelixRadius.rect(FelixRadius.card))
        .shadow(color: FelixColors.shadow.opacity(isActive ? 1 : 0),
                radius: 12, y: 4)
        .opacity(panelOpacity)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: panel.state)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: panel.title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: panel.subtitle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var panelOpacity: Double {
        switch panel.state {
        case .active:   return 1
        case .complete: return 0.72
        case .failed:   return 0.85
        }
    }

    @ViewBuilder
    private var statusMark: some View {
        switch panel.state {
        case .active:
            ActiveSpinner()
        case .complete:
            Image(systemName: "checkmark.circle")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(FelixColors.textSecondary)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(FelixColors.destructive)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    private var accessibilityText: String {
        let state: String
        switch panel.state {
        case .active:   state = "in progress"
        case .complete: state = "done"
        case .failed:   state = "failed"
        }
        return "\(panel.title), \(state). \(panel.subtitle)"
    }
}

/// The concluding panel — visually distinct from the working panels. Its
/// title is the user's original request verbatim; its body is the outcome in
/// plain language, with a working link when a real result exists.
private struct FinalPanelView: View {
    let panel: Panel
    @Environment(\.openURL) private var openURL

    private var failed: Bool { panel.state == .failed }

    var body: some View {
        VStack(alignment: .leading, spacing: FelixSpacing.md) {
            HStack(alignment: .top, spacing: FelixSpacing.md) {
                Image(systemName: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.title3.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(failed ? FelixColors.destructive : FelixColors.tintStrong)
                    .padding(.top, 2)

                Text("\u{201C}\(panel.title)\u{201D}")
                    .font(FelixTypography.titleMedium)
                    .foregroundStyle(FelixColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !panel.body.isEmpty {
                Text(panel.body)
                    .font(FelixTypography.bodyLarge)
                    .foregroundStyle(FelixColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let link = panel.link {
                Button {
                    Haptics.light()
                    openURL(link)
                } label: {
                    HStack(spacing: FelixSpacing.sm) {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.medium))
                        Text("Open the result")
                            .font(FelixTypography.titleSmall)
                    }
                    .foregroundStyle(FelixColors.onTint)
                    .padding(.horizontal, FelixSpacing.lg)
                    .frame(height: 40)
                    .background(FelixColors.tint, in: Capsule())
                }
                .buttonStyle(.felixPress)
                .accessibilityLabel("Open the result in your browser")
            }
        }
        .padding(FelixSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            FelixRadius.rect(FelixRadius.card).fill(FelixColors.surfaceProminent)
        )
        .felixGlass(in: FelixRadius.rect(FelixRadius.card))
        .shadow(color: FelixColors.shadow, radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Small display-refresh-synced spinner for the active panel — a short arc of
/// the same line quality as the scribble, no UIKit activity indicator.
private struct ActiveSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(FelixColors.tintStrong,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 17, height: 17)
                .rotationEffect(.radians(reduceMotion ? 0 : t * 4))
        }
        .accessibilityHidden(true)
    }
}
