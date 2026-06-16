import Foundation

enum RepoLocator {
    private static let savedKey = "felixRepoRoot"

    static func findRepoRoot() -> URL? {
        if let saved = UserDefaults.standard.string(forKey: savedKey) {
            let url = URL(fileURLWithPath: saved)
            if hasBackend(at: url) { return url }
        }

        if let bundled = Bundle.main.object(forInfoDictionaryKey: "FelixRepoRoot") as? String {
            let url = URL(fileURLWithPath: bundled)
            if hasBackend(at: url) { return save(url) }
        }

        if let env = ProcessInfo.processInfo.environment["FELIX_REPO_ROOT"] {
            let url = URL(fileURLWithPath: env)
            if hasBackend(at: url) { return save(url) }
        }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/GitHub/tillyhackswinners"),
            home.appendingPathComponent("Desktop/tillyhackswinners"),
            home.appendingPathComponent("tillyhackswinners"),
        ]
        for root in candidates where hasBackend(at: root) {
            return save(root)
        }

        var url = Bundle.main.bundleURL
        for _ in 0..<12 {
            if hasBackend(at: url) { return save(url) }
            url.deleteLastPathComponent()
        }
        return nil
    }

    @discardableResult
    private static func save(_ root: URL) -> URL {
        UserDefaults.standard.set(root.path, forKey: savedKey)
        return root
    }

    private static func hasBackend(at root: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent("backend/venv/bin/uvicorn").path
        )
    }
}
