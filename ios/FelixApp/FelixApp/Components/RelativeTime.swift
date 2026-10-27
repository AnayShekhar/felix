import Foundation

/// Richer relative timestamps for the rebuilt UI ("Just now", "2 minutes ago",
/// "Yesterday at 3:41 PM"). Extends the shared `RelativeTime` enum (defined in
/// shared/Constants.swift) rather than redeclaring it.
extension RelativeTime {
    private static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static func friendly(_ unix: Double?) -> String {
        guard let unix, unix > 0 else { return "" }
        let date = Date(timeIntervalSince1970: unix)
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            if Date().timeIntervalSince(date) < 60 { return "Just now" }
            return string(fromUnix: unix)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at \(dayTime.string(from: date))"
        }
        return string(fromUnix: unix)
    }
}
