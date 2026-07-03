import SwiftUI

/// Legacy navigation sections (the tab bar was replaced by the sidebar shell).
enum LumisTab: Int, CaseIterable {
    case home, history, settings
}

/// Category of an action, used for the icon + accent color on cards.
enum ActionType: String, Codable {
    case spreadsheet, email, calendar, file, web, note, reminder, media, system, other

    /// Map a backend tool name to a category.
    static func from(tool: String?) -> ActionType {
        guard let t = tool else { return .other }
        if t.hasPrefix("numbers") { return .spreadsheet }
        if t.hasPrefix("gmail") { return .email }
        if t.hasPrefix("calendar") { return .calendar }
        if t.hasPrefix("finder") || t.hasPrefix("notes") || t == "ios.create_note" { return .file }
        if t.hasPrefix("web") || t.hasPrefix("browser") || t.hasPrefix("screen") { return .web }
        if t.hasPrefix("reminders") || t == "ios.create_reminder" { return .reminder }
        if t.hasPrefix("media") { return .media }
        if t.hasPrefix("system") || t.hasPrefix("clipboard") { return .system }
        if t.hasPrefix("ios.create_note") { return .note }
        return .other
    }

    var symbol: String {
        switch self {
        case .spreadsheet: return "tablecells.fill"
        case .email:       return "envelope.fill"
        case .calendar:    return "calendar"
        case .file:        return "folder.fill"
        case .web:         return "globe"
        case .note:        return "note.text"
        case .reminder:    return "checklist"
        case .media:       return "music.note"
        case .system:      return "gearshape.fill"
        case .other:       return "checkmark.seal.fill"
        }
    }

    /// One disciplined accent for every category — the SF Symbol already
    /// carries the category information, so a per-category rainbow added
    /// noise without real information value. Deliberate consolidation.
    var tint: Color { LumisColors.tint }
}

/// A completed action, surfaced in the Home result card.
struct ActionResult: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var description: String
    var actionType: ActionType
    var success: Bool
    var deeplink: URL?

    static func == (lhs: ActionResult, rhs: ActionResult) -> Bool { lhs.id == rhs.id }

    /// Build from a backend step result.
    init(step: StepResult) {
        let label = toolMeta(step.tool).label
        self.title = step.title ?? label
        self.description = step.message ?? step.summary ?? ""
        self.actionType = ActionType.from(tool: step.tool)
        self.success = (step.status != "error")
        self.deeplink = step.url.flatMap { URL(string: $0) }
    }

    init(title: String, description: String, actionType: ActionType, success: Bool, deeplink: URL? = nil) {
        self.title = title
        self.description = description
        self.actionType = actionType
        self.success = success
        self.deeplink = deeplink
    }
}
