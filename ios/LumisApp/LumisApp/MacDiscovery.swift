import Foundation
import Combine

@MainActor
final class MacDiscovery: NSObject, ObservableObject {
    @Published private(set) var baseURL: String?
    @Published private(set) var statusText = "Searching for Mac…"

    private let browser = NetServiceBrowser()
    private var resolving: NetService?

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        baseURL = nil
        statusText = "Searching for Mac…"
        browser.stop()
        browser.searchForServices(ofType: "_lumis._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        resolving?.stop()
        resolving = nil
    }

    private func resolve(_ service: NetService) {
        resolving?.stop()
        resolving = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
}

extension MacDiscovery: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        Task { @MainActor in
            self.statusText = "Found \(service.name)…"
            self.resolve(service)
        }
    }

    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        Task { @MainActor in
            self.statusText = "Open Lumis on your Mac (same WiFi)"
        }
    }

    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        Task { @MainActor in
            if self.baseURL != nil {
                self.baseURL = nil
                self.statusText = "Mac disconnected — searching…"
                self.browser.searchForServices(ofType: "_lumis._tcp.", inDomain: "local.")
            }
        }
    }
}

extension MacDiscovery: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        let port = sender.port
        guard !host.isEmpty, port > 0 else { return }
        Task { @MainActor in
            self.baseURL = "http://\(host):\(port)"
            self.statusText = "Connected to \(sender.name)"
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in
            self.statusText = "Could not reach Mac — open Lumis on your Mac"
        }
    }
}
