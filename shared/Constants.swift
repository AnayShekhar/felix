import SwiftUI

// Shared design + configuration constants for the Lumis iOS app.
// Keep it free of platform-specific APIs so it stays easy to reuse.

enum LumisBrand {
    // MARK: Palette — mirrors iOS `LumisColors` raw palette (Carbon #212222,
    // Alabaster #DBDDDE, Cool Steel #99ACBE). These are the LIGHT-mode
    // resolutions; in-app use should go through the adaptive `LumisColors`
    // tokens, which handle dark mode.

    /// Primary light-mode background. Alabaster, #DBDDDE.
    static let alabaster = Color(red: 0.859, green: 0.867, blue: 0.871)

    /// The single brand accent — Cool Steel, #99ACBE. Identical in both modes.
    static let accent = Color(red: 0.600, green: 0.675, blue: 0.745)

    /// A softer steel used for gradients, glows, and hover states.
    static let accentSoft = Color(red: 0.600, green: 0.675, blue: 0.745).opacity(0.55)

    /// Primary text / icon ink. Carbon, #212222.
    static let ink = Color(red: 0.129, green: 0.133, blue: 0.133)
    static let inkSecondary = Color(red: 0.129, green: 0.133, blue: 0.133).opacity(0.55)

    // Card + hairline surfaces tuned for the light background.
    static let surface = Color(red: 0.129, green: 0.133, blue: 0.133).opacity(0.05)
    static let surfaceHover = Color(red: 0.129, green: 0.133, blue: 0.133).opacity(0.04)
    static let hairline = Color(red: 0.129, green: 0.133, blue: 0.133).opacity(0.10)

    /// Status colors used for connection + tool result dots.
    static let online = Color(red: 0.298, green: 0.686, blue: 0.490)   // #4CAF7D
    static let offline = Color(red: 0.129, green: 0.133, blue: 0.133).opacity(0.30)
    static let error = Color(red: 0.878, green: 0.322, blue: 0.322)    // #E05252

    /// Amber reserved for the "Mac linked but offline" state (matches iOS).
    static let amber = Color(red: 0.910, green: 0.659, blue: 0.220)    // #E8A838

    /// Persistence + networking defaults (matches CLAUDE.md API contract).
    static let defaultBackendURL = "https://lumis-production-b878.up.railway.app"
    static let backendURLKey = "lumis.backendURL"
    static let notifyCompletionKey = "lumis.notify.completion"
    static let notifyErrorsKey = "lumis.notify.errors"
    /// Bearer token for the signed-in account (shared by AuthStore + APIService).
    static let authTokenKey = "lumis.auth.token"

    /// Google OAuth client ID (same client the iOS app uses, so Mac sign-in
    /// lands in the same Lumis account).
    static let googleClientID = "955535830862-t9jp1lql7ert69up16jr27pj248f58fi.apps.googleusercontent.com"

    static let appVersion = "1.1"
}

/// Maps backend tool names (e.g. "media.open_spotify") to an SF Symbol + tint so
/// every surface renders the same tool identically.
enum ToolStyle {
    static func icon(for tool: String?) -> String {
        switch tool ?? "" {
        case "notes.create_from_image":     return "note.text"
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
        case "media":   return Color(red: 0.34, green: 0.82, blue: 0.46)
        case "gmail":   return Color(red: 0.94, green: 0.40, blue: 0.36)
        case "browser": return Color(red: 0.36, green: 0.66, blue: 0.96)
        case "slides":  return Color(red: 0.96, green: 0.58, blue: 0.26)
        case "numbers": return Color(red: 0.40, green: 0.80, blue: 0.70)
        case "ios":     return Color(red: 0.58, green: 0.56, blue: 0.98)
        default:        return LumisBrand.accent
        }
    }

    private static func iconByPrefix(_ tool: String?) -> String {
        let prefix = (tool ?? "").split(separator: ".").first.map(String.init) ?? ""
        switch prefix {
        case "notes":   return "note.text"
        case "media":   return "music.note"
        case "gmail":   return "envelope.fill"
        case "browser": return "safari.fill"
        case "slides":  return "rectangle.on.rectangle.angled"
        case "numbers": return "tablecells.fill"
        case "calendar": return "calendar"
        case "reminders": return "checklist"
        case "contacts": return "person.crop.circle"
        case "ios":     return "iphone"
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

    /// "media.open_spotify" -> "Media · Open Spotify"
    static func prettyToolName(_ tool: String) -> String {
        let parts = tool.split(separator: ".")
        return parts.map { seg in
            seg.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }.joined(separator: " · ")
    }
}

/// Human-readable formatting for learned-memory keys/values, shared by the iOS
/// Settings memory list and the Mac Memory table so both read identically.
enum MemoryFormat {
    private static let labels: [String: String] = [
        "command_patterns": "Common Commands",
        "default_browser": "Default Browser",
        "frequent_contacts": "Frequent Contacts",
        "last_email_recipient": "Last Email Recipient",
        "expense_file": "Expense File",
        "expense_file_path": "Expense File",
        "preferred_calendar": "Default Calendar",
        "preferred_reminder_list": "Default Reminder List",
        "music_service": "Music Service",
        "home_folder": "Home Folder",
    ]

    /// "command_patterns" -> "Common Commands" (curated), else title-cased.
    static func prettyKey(_ key: String) -> String {
        if let label = labels[key] { return label }
        return key.split(whereSeparator: { $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// A stored JSON-array value (e.g. `["a","b"]`) becomes "a, b"; plain values
    /// pass through unchanged.
    static func prettyValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.map { String(describing: $0) }.joined(separator: ", ")
        }
        return value
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
