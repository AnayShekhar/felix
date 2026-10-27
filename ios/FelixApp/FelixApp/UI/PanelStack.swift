import Combine
import Foundation
import SwiftUI

/// One live status panel in a request's stack. Each discrete step the agent
/// takes becomes a panel; the last panel of a finished request is the `final`
/// one (the user's request verbatim + the plain-language outcome).
struct Panel: Identifiable, Codable, Equatable {
    enum State: String, Codable { case active, complete, failed }

    var id = UUID()
    /// Short dynamic status word while active ("Working," "Researching," …).
    var title: String
    /// One slightly-more-specific line, always plain human language.
    var subtitle: String
    var state: State = .active
    /// True only for the concluding panel of the stack.
    var isFinal = false
    /// Final panel: the plain-language result body.
    var body: String = ""
    /// Final panel: a real link to the outcome, when one exists.
    var link: URL?
}

/// One user request and the ordered panels it produced. Archived whole into
/// Past Chats so the user can look back at exactly what happened.
struct ChatStack: Identifiable, Codable, Equatable {
    var id = UUID()
    /// The user's original request, verbatim.
    var request: String
    var startedAt = Date()
    var panels: [Panel] = []

    /// Finished when the stack's LAST panel is a concluding one. A continued
    /// past chat holds an earlier final panel mid-stack, so "contains a final
    /// panel" would wrongly freeze it; only the tail decides.
    var isFinished: Bool { panels.last?.isFinal == true }

    /// Index of the currently active panel, if any.
    var activeIndex: Int? { panels.lastIndex { $0.state == .active } }
}

/// Plain-language status word for a tool the agent just picked. Never
/// technical or implementation-flavored.
enum PanelWording {
    static func title(forTool tool: String?) -> String {
        guard let t = tool else { return "Working" }
        if t.hasPrefix("web.research") || t.hasPrefix("web.search") { return "Researching" }
        if t.contains("read") || t.hasPrefix("web.fetch") || t.hasPrefix("drive.search")
            || t.hasPrefix("people.search") { return "Reading" }
        if t.hasPrefix("docs.") || t.hasPrefix("notion.") || t == "ios.create_note" { return "Writing" }
        if t.hasPrefix("gmail.") { return "Emailing" }
        if t.hasPrefix("sheets.") { return "Updating a sheet" }
        if t.hasPrefix("calendar.") || t.hasPrefix("tasks.") || t == "ios.create_reminder" { return "Scheduling" }
        if t.hasPrefix("browser.") || t.hasPrefix("linkedin.") || t.hasPrefix("slack.")
            || t.hasPrefix("airtable.") { return "Browsing" }
        if t.hasPrefix("media.") { return "Playing" }
        if t.hasPrefix("ios.") { return "Handing off" }
        return "Working"
    }

    /// Human fallback when the backend didn't send a plain-language line.
    static func subtitle(forTool tool: String?) -> String {
        switch title(forTool: tool) {
        case "Researching":       return "Looking things up"
        case "Reading":           return "Going through what's there"
        case "Writing":           return "Putting words down"
        case "Emailing":          return "Working on your email"
        case "Updating a sheet":  return "Editing your spreadsheet"
        case "Scheduling":        return "Sorting out the timing"
        case "Browsing":          return "Working in the browser"
        case "Playing":           return "Getting your music ready"
        case "Handing off":       return "Opening this on your phone"
        default:                  return "Getting things moving"
        }
    }
}

/// Past Chats: every archived stack, newest first, persisted on device so the
/// user can reopen any past request exactly as it finished.
@MainActor
final class PastChatsStore: ObservableObject {
    @Published private(set) var chats: [ChatStack] = []

    private nonisolated static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("past-chats.json")
    }

    init() { load() }

    /// Archive a stack (replacing any earlier copy of the same stack, so a
    /// reopened chat never duplicates itself). Keeps the newest 100.
    func archive(_ stack: ChatStack) {
        guard !stack.panels.isEmpty else { return }
        chats.removeAll { $0.id == stack.id }
        chats.insert(stack, at: 0)
        if chats.count > 100 { chats.removeLast(chats.count - 100) }
        save()
    }

    func delete(_ stack: ChatStack) {
        chats.removeAll { $0.id == stack.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([ChatStack].self, from: data) else { return }
        chats = decoded
    }

    private func save() {
        let snapshot = chats
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
