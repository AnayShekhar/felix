import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for task-completion / error alerts.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func handle(_ event: FeedEvent, notifyCompletion: Bool, notifyErrors: Bool) {
        if event.isError, notifyErrors {
            post(title: "Felix hit a problem", body: event.message)
        } else if event.event == "workflow_complete", notifyCompletion {
            post(title: "Felix finished", body: event.message)
        } else if event.event == "task_complete", notifyCompletion {
            post(title: "Task complete", body: event.message)
        }
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
