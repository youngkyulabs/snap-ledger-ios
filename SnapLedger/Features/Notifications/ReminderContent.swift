import Foundation

enum ReminderContent {
    static let identifier = "com.youngkyu.snapledger.nightly-reminder"
    static let title = "찰칵가계부"

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
