import UserNotifications

/// 앱이 foreground일 때 예산 임계 알림을 시스템 배너로 띄우기 위한 델리게이트.
/// iOS는 기본적으로 foreground에선 배너를 누르므로, 저장 직후(앱 사용 중) 보이게 하려면
/// willPresent에서 표시 옵션을 직접 반환해야 한다. 예산 알림만 배너로 띄우고
/// 나머지(야간 리마인더 등)는 foreground에서 굳이 보여주지 않는다.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier == BudgetAlertContent.categoryIdentifier {
            return [.banner, .sound]
        }
        return []
    }
}
