import SwiftUI
import UIKit

/// Single source of truth for every color in the app.
///
/// Three raw colors define the whole palette:
///   Carbon Black  #212222 · Alabaster #DBDDDE · Cool Steel #99ACBE
///
/// Light mode: pure white background, Carbon text, with Alabaster repurposed
/// as the elevated-surface tone. Dark mode: Carbon background, Alabaster text.
/// The tint (Cool Steel) is the one constant accent in both modes.
/// Every other file references the semantic names below — never a raw hex.
struct LumisColors {
    // MARK: Raw palette (private — nothing outside this file touches these)
    private static let carbon    = UIColor(hex: "#212222")
    private static let alabaster = UIColor(hex: "#DBDDDE")
    private static let coolSteel = UIColor(hex: "#99ACBE")

    // MARK: Semantic tokens — adaptive (follow the trait environment)

    /// Primary screen background — pure white in light mode.
    static let background = adaptive(light: .white, dark: carbon)
    /// Elevated surface (cards, the chat bar, sheets). Light mode: the
    /// Alabaster tone lifted toward white, so cards sit visibly on the pure
    /// white page without turning heavy grey. Dark: a clearly lifted grey.
    static let surface = adaptive(light: blend(alabaster, .white, 0.40),
                                  dark: blend(carbon, alabaster, 0.09))
    /// Primary text and icons.
    static let textPrimary = adaptive(light: carbon, dark: alabaster)
    /// Secondary text (supporting copy, subtitles). A real color, never the
    /// primary at reduced opacity — opacity drifts across surfaces.
    static let textSecondary = adaptive(light: blend(carbon, .white, 0.33),
                                        dark: blend(alabaster, carbon, 0.33))
    /// Tertiary text (timestamps, placeholders, disabled). Real color, not opacity.
    static let textTertiary = adaptive(light: blend(carbon, .white, 0.55),
                                       dark: blend(alabaster, carbon, 0.55))
    /// Hairline dividers and card strokes. Real color, not opacity, so the
    /// hairline reads identically on every surface.
    static let divider = adaptive(light: blend(carbon, .white, 0.88),
                                  dark: blend(alabaster, carbon, 0.82))

    // MARK: Tint — constant across both modes (like Claude's one orange)

    /// The single brand accent. Identical in light and dark.
    static let tint = Color(uiColor: coolSteel)
    /// The accent at full confidence — deepened toward Carbon in light mode
    /// (raw Cool Steel is too close to Alabaster to hold a line), lifted
    /// toward Alabaster in dark. For linework and emphasis (the scribble,
    /// the active spinner), not fills.
    static let tintStrong = adaptive(light: blend(coolSteel, carbon, 0.38),
                                     dark: blend(coolSteel, alabaster, 0.22))
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
    /// Drop shadow color — almost invisible (HIG: depth is suggested, never
    /// drawn). Use with small radii (8–12) and a 4pt Y offset.
    static let shadow = Color.black.opacity(0.04)
    /// Skeleton shimmer highlight (screen-blended, works on both modes).
    static let shimmer = Color(uiColor: alabaster).opacity(0.55)

    // MARK: Status colors (functional, not decorative)

    /// The one semantic exception to the single accent: errors and destructive
    /// actions only. Success/connected states use the tint (with a checkmark
    /// glyph carrying the meaning) — never a second hue.
    static let destructive = Color(hex: "#E05252")

    // MARK: -

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// Linear blend of two raw palette colors (t = 0 → a, t = 1 → b).
    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
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
