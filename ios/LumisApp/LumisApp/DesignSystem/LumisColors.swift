import SwiftUI
import UIKit

/// Single source of truth for every color in the app.
///
/// Three raw colors define the whole palette:
///   Carbon Black  #212222 · Alabaster #DBDDDE · Cool Steel #99ACBE
///
/// Light mode: Alabaster background, Carbon text. Dark mode: swapped.
/// The tint (Cool Steel) is the one constant accent in both modes.
/// Every other file references the semantic names below — never a raw hex.
struct LumisColors {
    // MARK: Raw palette (private — nothing outside this file touches these)
    private static let carbon    = UIColor(hex: "#212222")
    private static let alabaster = UIColor(hex: "#DBDDDE")
    private static let coolSteel = UIColor(hex: "#99ACBE")

    // MARK: Semantic tokens — adaptive (follow the trait environment)

    /// Primary screen background.
    static let background = adaptive(light: alabaster, dark: carbon)
    /// Card / grouped-section surface, one step off the background.
    static let surface = adaptive(light: carbon.withAlphaComponent(0.05),
                                  dark: alabaster.withAlphaComponent(0.07))
    /// Primary text and icons.
    static let textPrimary = adaptive(light: carbon, dark: alabaster)
    /// Secondary text (supporting copy, subtitles).
    static let textSecondary = textPrimary.opacity(0.55)
    /// Tertiary text (timestamps, placeholders, disabled).
    static let textTertiary = textPrimary.opacity(0.35)
    /// Hairline dividers and card strokes.
    static let divider = textPrimary.opacity(0.10)

    // MARK: Tint — constant across both modes (like Claude's one orange)

    /// The single brand accent. Identical in light and dark.
    static let tint = Color(uiColor: coolSteel)
    /// Subtle tint wash (icon chips, selected rows).
    static let tintSoft = tint.opacity(0.16)
    /// Mid-strength tint (secondary fills).
    static let tintMid = tint.opacity(0.55)
    /// Ink drawn on top of a solid tint fill — Carbon in both modes
    /// (Cool Steel is light, so dark ink keeps contrast everywhere).
    static let onTint = Color(uiColor: carbon)

    // MARK: Fixed utility tokens

    /// Dimming layer behind the sidebar / modals — always dark.
    static let scrim = Color(uiColor: carbon).opacity(0.40)
    /// Soft drop shadow color.
    static let shadow = Color.black.opacity(0.10)
    /// Skeleton shimmer highlight (screen-blended, works on both modes).
    static let shimmer = Color(uiColor: alabaster).opacity(0.55)

    // MARK: Status colors (functional, not decorative)

    static let destructive = Color(hex: "#E05252")
    static let success     = Color(hex: "#4CAF7D")
    static let amber       = Color(hex: "#E8A838")

    // MARK: -

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// The user's appearance preference, persisted in Settings ("Appearance").
/// `.system` follows the OS; `.light` / `.dark` force a scheme app-wide.
enum LumisAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "lumis.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r)/255, green: CGFloat(g)/255,
                  blue: CGFloat(b)/255, alpha: CGFloat(a)/255)
    }
}
