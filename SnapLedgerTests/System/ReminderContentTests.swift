import Testing
import UserNotifications
@testable import SnapLedger

@Suite
struct ReminderContentTests {
    @Test func triggerFiresOnceAtGivenTime() {
        let trigger = ReminderContent.trigger(hour: 21, minute: 30)
        #expect(trigger.repeats == false)
        #expect(trigger.dateComponents.hour == 21)
        #expect(trigger.dateComponents.minute == 30)
    }

    @Test func zeroPendingHasIdleBody() {
        #expect(ReminderContent.body(pendingCount: 0) == "오늘 검토할 항목이 없어요.")
    }

    @Test func bodyMentionsCount() {
        #expect(ReminderContent.body(pendingCount: 1).contains("1건"))
        #expect(ReminderContent.body(pendingCount: 7).contains("7건"))
    }

    @Test func shouldScheduleOnlyWhenPositive() {
        #expect(ReminderContent.shouldSchedule(pendingCount: 0) == false)
        #expect(ReminderContent.shouldSchedule(pendingCount: 1) == true)
        #expect(ReminderContent.shouldSchedule(pendingCount: 100) == true)
    }
}
