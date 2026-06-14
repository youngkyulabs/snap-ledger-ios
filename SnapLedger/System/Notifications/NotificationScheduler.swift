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

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func clear() {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderContent.identifier])
    }

    /// 검토 항목을 저장하기 시작하면 알림 센터에 이미 도착해 있는 리마인더를 지운다.
    /// 예약(pending)이 아니라 이미 발사돼 알림 센터에 떠 있는(delivered) 알림 대상.
    func clearDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [ReminderContent.identifier])
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

        let trigger = ReminderContent.trigger(hour: hour, minute: minute)

        let request = UNNotificationRequest(
            identifier: ReminderContent.identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
