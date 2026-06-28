import Foundation

enum Config {
    // 🔧 After deploying to Cloud Run, paste your service URL here.
    //    e.g. "https://lumis-backend-abc123-uc.a.run.app"
    //    For LAN testing against your Mac instead, use "http://<your-mac-ip>:8000".
    static let baseURL = "https://exciting-essential-writing.ngrok-free.dev"


    static var ingestURL: URL { URL(string: "\(baseURL)/ingest")! }

    static var wsURL: URL {
        // https -> wss, http -> ws
        let ws = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(ws)/ws")!
    }
}
