import Foundation

enum Config {
    // Current Lumis backend (Railway). The live app lives in ios/LumisApp —
    // this ios/Lumis sample folder is legacy and not built by the Xcode project.
    static let baseURL = "https://lumis-production-b878.up.railway.app"

    static var ingestURL: URL { URL(string: "\(baseURL)/ingest")! }

    static var wsURL: URL {
        let ws = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(ws)/ws")!
    }
}
