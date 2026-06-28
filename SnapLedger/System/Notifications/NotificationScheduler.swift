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

    /// 저장한 카테고리가 예산 임계점(near/over)에 닿았을 때 즉시 로컬 알림을 보낸다.
    /// 여유(under)면 보내지 않고, 권한 미허용 시에도 조용히 무시한다.
    /// trigger를 nil로 둬 곧바로 발사되고, 같은 카테고리는 식별자가 같아 교체된다(쌓이지 않음).
    func notifyBudgetThreshold(_ line: BudgetProgress.Line) async {
        guard line.state != .under else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = BudgetAlertContent.title(for: line.state)
        content.body = BudgetProgress.alertSummary(for: line)
        content.sound = .default
        content.categoryIdentifier = BudgetAlertContent.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: BudgetAlertContent.identifier(for: line.category),
            content: content,
            trigger: nil
        )
        try? await center.add(request)
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
