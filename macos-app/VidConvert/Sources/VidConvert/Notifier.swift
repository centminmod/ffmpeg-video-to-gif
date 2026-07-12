// M3: completion notifications — posted only while the app is in the background
// (if the user is looking at the window, the row already tells them).

import AppKit
import UserNotifications

@MainActor
enum Notifier {
    /// UNUserNotificationCenter traps when the process has no bundle (the
    /// `swift run` dev loop) — every call guards on a real bundle identifier.
    private static let available = Bundle.main.bundleIdentifier != nil

    /// Called at launch so the permission prompt appears up front, not mid-queue.
    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postIfBackground(title: String, body: String) {
        guard available, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: content, trigger: nil))
    }
}
