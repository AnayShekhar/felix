import Foundation

@MainActor
final class BackendManager: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var errorMessage: String?

    private var process: Process?
    private let port = 8000

    var portNumber: Int { port }

    func start(repoRoot: URL) {
        guard !running else { return }

        if Self.isHealthy() {
            running = true
            errorMessage = nil
            return
        }

        let uvicorn = repoRoot.appendingPathComponent("backend/venv/bin/uvicorn")
        guard FileManager.default.fileExists(atPath: uvicorn.path) else {
            errorMessage = "Backend not found. Run: cd backend && python3 -m venv venv && pip install -r requirements.txt"
            return
        }

        let proc = Process()
        proc.executableURL = uvicorn
        proc.arguments = ["main:app", "--port", "\(port)", "--host", "0.0.0.0"]
        proc.currentDirectoryURL = repoRoot.appendingPathComponent("backend")
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        do {
            try proc.run()
            process = proc
            running = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start backend: \(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        running = false
    }

    private static func isHealthy() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8000/health"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("ok")
    }
}
