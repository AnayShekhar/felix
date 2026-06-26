import SwiftUI

// Shared design + configuration constants for Felix's macOS and iOS frontends.
// This single file is referenced by BOTH the macOS app (macos-app/Felix) and
// the iOS app (ios/FelixApp) so the brand color and tool styling stay identical
// across surfaces. Keep it free of platform-specific APIs so it compiles on both.

enum FelixBrand {
    /// Felix's single brand accent — a warm, premium amber ("Felix Amber", #F59E21).
    /// Deliberately not blue and not purple.
    static let accent = Color(red: 0.961, green: 0.620, blue: 0.129)

    /// A lighter amber used for gradients, glows, and hover states.
    static let accentSoft = Color(red: 0.984, green: 0.745, blue: 0.361)

    /// Status colors used for connection + tool result dots.
    static let online = Color(red: 0.30, green: 0.85, blue: 0.46)
    static let offline = Color(red: 0.55, green: 0.57, blue: 0.62)
    static let error = Color(red: 0.95, green: 0.36, blue: 0.33)

    /// Persistence + networking defaults (matches CLAUDE.md API contract).
    static let defaultBackendURL = "https://felix-production-38e6.up.railway.app"
    static let backendURLKey = "felix.backendURL"
    static let notifyCompletionKey = "felix.notify.completion"
    static let notifyErrorsKey = "felix.notify.errors"

    static let appVersion = "1.1"
}

/// Maps backend tool names (e.g. "spotify.play_song") to an SF Symbol + tint so
/// every surface renders the same tool identically.
enum ToolStyle {
    static func icon(for tool: String?) -> String {
        switch tool ?? "" {
        case "notes.create_from_image":     return "note.text"
        case "spotify.play_song":           return "music.note"
        case "gmail.draft_email":           return "envelope.fill"
        case "browser.open_url":            return "safari.fill"
        case "slides.create_presentation":  return "rectangle.on.rectangle.angled"
        case "numbers.create_spreadsheet":  return "tablecells.fill"
        case "numbers.add_expense":         return "dollarsign.circle.fill"
        default:
            return iconByPrefix(tool)
        }
    }

    static func tint(for tool: String?) -> Color {
        switch (tool ?? "").split(separator: ".").first.map(String.init) ?? "" {
        case "notes":   return Color(red: 0.98, green: 0.78, blue: 0.20)
        case "spotify": return Color(red: 0.34, green: 0.82, blue: 0.46)
        case "gmail":   return Color(red: 0.94, green: 0.40, blue: 0.36)
        case "browser": return Color(red: 0.36, green: 0.66, blue: 0.96)
        case "slides":  return Color(red: 0.96, green: 0.58, blue: 0.26)
        case "numbers": return Color(red: 0.40, green: 0.80, blue: 0.70)
        default:        return FelixBrand.accent
        }
    }

    private static func iconByPrefix(_ tool: String?) -> String {
        let prefix = (tool ?? "").split(separator: ".").first.map(String.init) ?? ""
        switch prefix {
        case "notes":   return "note.text"
        case "spotify": return "music.note"
        case "gmail":   return "envelope.fill"
        case "browser": return "safari.fill"
        case "slides":  return "rectangle.on.rectangle.angled"
        case "numbers": return "tablecells.fill"
        default:        return "sparkles"
        }
    }
}

/// A short, human one-liner describing a result, falling back through the
/// fields the backend may populate.
enum ToolSummary {
    static func line(title: String?, message: String?, tool: String?) -> String {
        if let t = title, !t.isEmpty { return t }
        if let m = message, !m.isEmpty { return m }
        if let tool, !tool.isEmpty { return prettyToolName(tool) }
        return "Action"
    }

    /// "spotify.play_song" -> "Spotify · Play Song"
    static func prettyToolName(_ tool: String) -> String {
        let parts = tool.split(separator: ".")
        return parts.map { seg in
            seg.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }.joined(separator: " · ")
    }
}

/// Relative time formatting shared by Activity/History rows ("2 min ago").
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(fromUnix ts: Double?) -> String {
        guard let ts, ts > 0 else { return "" }
        return formatter.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }
}
