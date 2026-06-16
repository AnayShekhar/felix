import Foundation

enum Config {
    static func ingestURL(base: String) -> URL {
        URL(string: "\(base)/ingest")!
    }

    static func wsURL(base: String) -> URL {
        let ws = base
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(ws)/ws")!
    }
}
