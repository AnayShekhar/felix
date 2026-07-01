import Foundation

/// Time-of-day greeting for the home hero. The phrase is chosen by the day of
/// the month (not random), so it stays the same all day and changes each day —
/// it feels intentional rather than jittery. Pass the user's name to personalize.
struct LumisGreeting {

    static func current(name: String?) -> String {
        let first = name?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        return timeBasedGreeting(hour: hour, name: first)
    }

    private static func timeBasedGreeting(hour: Int, name: String) -> String {
        let hasName = !name.isEmpty

        switch hour {
        case 5..<12:   // Morning
            return [
                hasName ? "Good morning, \(name)." : "Good morning.",
                "Ready when you are.",
                hasName ? "Morning, \(name)." : "Morning.",
                "What are we doing today?",
                "Let's get started.",
            ][dayIndex(mod: 5)]

        case 12..<17:  // Afternoon
            return [
                hasName ? "Good afternoon, \(name)." : "Good afternoon.",
                "Ready when you are.",
                "What can I do for you?",
                hasName ? "Afternoon, \(name)." : "Afternoon.",
                "Show me something.",
            ][dayIndex(mod: 5)]

        case 17..<21:  // Evening
            return [
                hasName ? "Good evening, \(name)." : "Good evening.",
                "Ready when you are.",
                hasName ? "Evening, \(name)." : "Evening.",
                "What's on your mind?",
                "What can I help with?",
            ][dayIndex(mod: 5)]

        default:       // Night
            return [
                "Working late?",
                "Ready when you are.",
                "Still here.",
                "What do you need?",
                hasName ? "Night, \(name)." : "Good night.",
            ][dayIndex(mod: 5)]
        }
    }

    /// Rotate by day of month — same phrase all day, changes each day.
    private static func dayIndex(mod: Int) -> Int {
        Calendar.current.component(.day, from: Date()) % mod
    }
}
