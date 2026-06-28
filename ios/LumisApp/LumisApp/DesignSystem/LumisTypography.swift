import SwiftUI

/// Type scale for the app. SF Pro only (system default), no custom fonts.
struct LumisTypography {
    // Display
    static let displayLarge  = Font.system(size: 34, weight: .semibold, design: .default)
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .default)

    // Title
    static let titleLarge    = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleMedium   = Font.system(size: 17, weight: .semibold, design: .default)
    static let titleSmall    = Font.system(size: 15, weight: .medium, design: .default)

    // Body
    static let bodyLarge     = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium    = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall     = Font.system(size: 13, weight: .regular, design: .default)

    // Caption
    static let caption       = Font.system(size: 12, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)

    // Mono
    static let mono          = Font.system(size: 13, weight: .regular, design: .monospaced)
}
