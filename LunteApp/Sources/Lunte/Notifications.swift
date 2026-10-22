import Foundation
import UserNotifications

/// Club notifications. Off when there's no bundle id (a bare `swift run`), where UserNotifications crashes.
enum Notifier {
    static let reacts = ["🧯", "😂", "🫂"]
    private static let delegate = Delegate() // the center holds its delegate weakly
    private static var on: Bool { Bundle.main.bundleIdentifier != nil }

    static func setUp() {
        guard on else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let actions = reacts.map { UNNotificationAction(identifier: $0, title: $0) }
        center.setNotificationCategories([UNNotificationCategory(identifier: "boom", actions: actions, intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// With `boom`, the notification gets the 🧯 😂 🫂 actions, each of which reacts to that Boom.
    static func post(_ title: String, _ body: String = "", boom: String? = nil) {
        guard on else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let boom {
            content.categoryIdentifier = "boom"
            content.userInfo = ["boom": boom]
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
            done([.banner, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler done: @escaping () -> Void) {
            let emoji = response.actionIdentifier
            if Notifier.reacts.contains(emoji), let boom = response.notification.request.content.userInfo["boom"] as? String {
                Task { try? await Relay.post(["type": "react", "boom": boom, "emoji": emoji]) } // ponytail: a failed react is dropped
            }
            done()
        }
    }
}
