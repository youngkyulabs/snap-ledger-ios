import Foundation
import UserNotifications

@MainActor
struct NotificationScheduler {
    let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func clear() {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderContent.identifier])
    }

    func syncIconBadge(count: Int) async {
        try? await center.setBadgeCount(max(0, count))
    }

    func refresh(hour: Int, minute: Int, pendingCount: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderContent.identifier])
        guard ReminderContent.shouldSchedule(pendingCount: pendingCount) else { return }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = ReminderContent.title
        content.body = ReminderContent.body(pendingCount: pendingCount)
        content.sound = .default
        content.badge = NSNumber(value: max(0, pendingCount))

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: ReminderContent.identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
