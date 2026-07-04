import SwiftUI

/// Spacing scale on Apple's 8pt grid (4 is the permitted half-step for tight
/// intra-element gaps). Use these instead of one-off magic numbers so padding
/// and gaps stay consistent across every screen.
enum LumisSpacing {
    /// 4 — tight intra-element gaps (label ↔ sublabel).
    static let xs: CGFloat = 4
    /// 8 — small gaps (chips, icon ↔ text) and internal card spacing.
    static let sm: CGFloat = 8
    /// 12 — default gap between sibling elements, internal card spacing.
    static let md: CGFloat = 12
    /// 16 — card padding, row insets.
    static let lg: CGFloat = 16
    /// 24 — gaps between sections.
    static let xl: CGFloat = 24
    /// 32 — hero padding, large vertical rhythm.
    static let xxl: CGFloat = 32
    /// 16 — standard leading/trailing screen margin (HIG), one value app-wide.
    static let screenMargin: CGFloat = 16
}

/// Corner radius scale. Every rounded rectangle in the app uses
/// `style: .continuous` — see `LumisRadius.rect(_:)`.
enum LumisRadius {
    /// 8 — small controls, skeleton bars.
    static let sm: CGFloat = 8
    /// 12 — compact chrome (toasts, small chips).
    static let md: CGFloat = 12
    /// 16 — buttons, sheets.
    static let lg: CGFloat = 16
    /// 24 — cards and panels.
    static let card: CGFloat = 24
    /// Fully rounded (capsules, dots).
    static let pill: CGFloat = .infinity

    /// The one way to make a rounded rect in this app: always `.continuous`
    /// (Apple's squircle curvature), never the generic circular corner.
    static func rect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// Press feedback for any tappable card or control: the HIG-style subtle
/// scale-down while pressed. Pair with the existing `Haptics` calls (or
/// `.sensoryFeedback`) — this style only handles the visual response.
struct LumisPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LumisPressStyle {
    /// `.buttonStyle(.lumisPress)` — plain content with a subtle press scale.
    static var lumisPress: LumisPressStyle { LumisPressStyle() }
}
