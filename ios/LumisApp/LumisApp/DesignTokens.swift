import SwiftUI
import UIKit

/// Phase 3 — Moonstone design system for the iOS app. Replaces the old amber
/// palette entirely. These tokens are the single source of truth for color,
/// typography, and the card blur across the rebuilt presentation layer. (The
/// macOS app keeps its own brand via shared Constants.swift — untouched.)
///
/// No amber anywhere. Dark mode only.
enum LumisColor {
    /// Deep blue-black — the inside of a high-end device, not pure black. #070B12
    static let background = Color(red: 0x07 / 255, green: 0x0B / 255, blue: 0x12 / 255)
    /// The orb's moonstone blue. #B8D9FF
    static let orbPrimary = Color(red: 0xB8 / 255, green: 0xD9 / 255, blue: 0xFF / 255)
    /// Soft halo color (use at ~20% opacity). #DDF6FF
    static let orbGlow = Color(red: 0xDD / 255, green: 0xF6 / 255, blue: 0xFF / 255)
    /// Cool metallic core. #9FB3C6
    static let coreMetallic = Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0xC6 / 255)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)

    /// Hairline card edge. #FFFFFF at 8%.
    static let cardBorder = Color.white.opacity(0.08)

    static let error = Color(red: 0xFF / 255, green: 0x44 / 255, blue: 0x44 / 255) // #FF4444
    static let success = orbPrimary
}

/// Typography tokens. SF Pro only — Heavy for headlines, Regular for body and
/// captions, Mono for any data display. No custom fonts.
enum LumisFont {
    static func headline(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Card background token: a real `UIBlurEffect(style: .dark)`, brighter and
/// darker than SwiftUI's `.ultraThinMaterial`. Used by frosted cards and the
/// Phase 8 result card / sheets.
struct DarkBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
