import SwiftUI

/// Single source of truth for every color in the app. Light "Parchment" theme.
/// Do not define colors anywhere else — reference `LumisColors.*`.
struct LumisColors {
    // Core palette
    static let parchment     = Color(hex: "#F8F3EE")  // Primary background
    static let powderBlue    = Color(hex: "#B0BFD1")  // Accents, active states, glows
    static let carbonBlack   = Color(hex: "#212222")  // Text, icons

    // Derived
    static let powderBlueLight   = Color(hex: "#B0BFD1").opacity(0.15)
    static let powderBlueMid     = Color(hex: "#B0BFD1").opacity(0.55)
    static let textSecondary     = Color(hex: "#212222").opacity(0.5)
    static let textTertiary      = Color(hex: "#212222").opacity(0.3)
    static let divider           = Color(hex: "#212222").opacity(0.08)
    static let cardBackground    = Color(hex: "#FFFFFF").opacity(0.6)
    static let destructive       = Color(hex: "#E05252")
    static let success           = Color(hex: "#4CAF7D")
    static let offline           = Color(hex: "#212222").opacity(0.25)

    /// Amber used for the "Mac linked but offline" state across the app.
    static let amber             = Color(hex: "#E8A838")
}

extension Color {
    init(hex: String) {
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
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
