import Foundation

@MainActor
final class BonjourAdvertiser: NSObject, ObservableObject {
    private var service: NetService?

    func start(port: Int) {
        stop()
        let name = Host.current().localizedName ?? "Felix Mac"
        let svc = NetService(domain: "local.", type: "_felix._tcp.", name: name, port: Int32(port))
        svc.includesPeerToPeer = true
        service = svc
        svc.publish()
    }

    func stop() {
        service?.stop()
        service = nil
    }
}
