import Foundation
import UserNotifications

enum ReminderContent {
    static let identifier = "com.youngkyu.snapledger.nightly-reminder"
    static let title = "찰칵가계부"

    /// Creates a one-shot trigger. Never use `repeats: true` — the baked-in pending count would go stale.
    static func trigger(hour: Int, minute: Int) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    static func body(pendingCount: Int) -> String {
        precondition(pendingCount >= 0)
        if pendingCount == 0 {
            return "오늘 검토할 항목이 없어요."
        }
        return "검토할 항목 \(pendingCount)건이 기다리고 있어요."
    }

    static func shouldSchedule(pendingCount: Int) -> Bool {
        pendingCount > 0
    }
}
