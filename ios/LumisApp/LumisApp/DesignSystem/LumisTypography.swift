import SwiftUI

/// Type scale for the app, built exclusively on Apple's semantic text styles
/// so every string scales with Dynamic Type. Hierarchy comes from the
/// semantic style plus at most a `.semibold`/`.medium` weight — never fixed
/// pixel sizes, never heavy bolding. New York (the system serif) is reserved
/// for the hero greeting.
struct LumisTypography {
    // Greeting — New York serif, hero moments only (the home greeting).
    static let greeting      = Font.system(.largeTitle, design: .serif)

    // Display — one per screen at most.
    static let displayLarge  = Font.system(.largeTitle).weight(.medium)
    static let displayMedium = Font.system(.title).weight(.medium)

    // Title
    static let titleLarge    = Font.system(.title2).weight(.medium)
    static let titleMedium   = Font.body.weight(.medium)           // 17 medium
    static let titleSmall    = Font.subheadline.weight(.medium)    // 15 medium

    // Body
    static let bodyLarge     = Font.body                           // 17
    /// Body-size emphasis (row labels, names). Medium — reserved so semibold
    /// stays exclusive to real titles and one heading can dominate per screen.
    static let bodyLargeEmphasized = Font.body.weight(.medium)
    static let bodyMedium    = Font.subheadline                    // 15
    static let bodySmall     = Font.footnote                       // 13

    // Caption
    static let caption       = Font.caption                        // 12
    static let captionMedium = Font.caption.weight(.medium)

    // Mono
    static let mono          = Font.system(.footnote, design: .monospaced)
}
