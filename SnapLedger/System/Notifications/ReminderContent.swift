import Foundation
import UserNotifications

enum ReminderContent {
    static let identifier = "com.youngkyu.snapledger.nightly-reminder"
    static let title = "찰칵가계부"

    /// 다음 1회만 발사하는 트리거. 반복(repeats: true) 예약은 콘텐츠에 박제된
    /// 과거 카운트를 앱이 갱신할 기회 없이 매일 재발송하므로 쓰지 않는다 —
    /// 앱이 다시 실행될 때마다 재예약하는 방식과 짝을 이룬다.
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
