import Foundation


enum Config {
    static func ingestURL(base: String) -> URL {
        URL(string: "\(base)/ingest")!
    }

    static func historyURL(base: String) -> URL {
        URL(string: "\(base)/history")!
    }

    static func taskURL(base: String) -> URL {
        URL(string: "\(base)/task")!
    }

    static func undoURL(base: String, actionID: Int) -> URL {
        URL(string: "\(base)/undo/\(actionID)")!
    }

    static func wsURL(base: String) -> URL {
        let ws = base
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(ws)/ws")!
    }
}
