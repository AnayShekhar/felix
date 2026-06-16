import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FelixController.shared.boot(openDashboard: true)
        notify("Felix is running — look for the ✓ icon in your menu bar (top right).")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if FelixController.shared.backend.running {
            FelixController.shared.dashboard.openInBrowser()
            notify("Felix is already running.")
        } else {
            FelixController.shared.boot(openDashboard: true)
        }
        return true
    }

    private func notify(_ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Felix"
        content.body = body
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(req)
    }
}
