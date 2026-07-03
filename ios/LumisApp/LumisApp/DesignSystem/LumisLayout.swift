import SwiftUI

/// Spacing scale. Use these instead of one-off magic numbers so padding and
/// gaps stay consistent across every screen.
enum LumisSpacing {
    /// 4 — tight intra-element gaps (label ↔ sublabel).
    static let xs: CGFloat = 4
    /// 8 — small gaps (chips, icon ↔ text).
    static let sm: CGFloat = 8
    /// 12 — default gap between sibling elements.
    static let md: CGFloat = 12
    /// 16 — card padding, row insets.
    static let lg: CGFloat = 16
    /// 24 — screen edge margins, gaps between sections.
    static let xl: CGFloat = 24
    /// 32 — hero padding, large vertical rhythm.
    static let xxl: CGFloat = 32
}

/// Corner radius scale.
enum LumisRadius {
    /// 8 — small controls, skeleton bars.
    static let sm: CGFloat = 8
    /// 12 — compact cards, toasts.
    static let md: CGFloat = 12
    /// 16 — cards, sheets, buttons.
    static let lg: CGFloat = 16
    /// Fully rounded (capsules, dots).
    static let pill: CGFloat = .infinity
}
