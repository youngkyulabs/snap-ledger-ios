// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Verifies review date classification.
struct ReviewDateStatusTests {
    // Reference dates use noon in current calendar.
    private let calendar = Calendar.current
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
    )!

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    @Test func todayIsToday() {
        #expect(ReviewDateCheck.status(for: day(0), now: now, calendar: calendar) == .today)
    }

    @Test func yesterdayIsYesterday() {
        #expect(ReviewDateCheck.status(for: day(-1), now: now, calendar: calendar) == .yesterday)
    }

    @Test func dayBeforeYesterdayIsTooOld() {
        #expect(ReviewDateCheck.status(for: day(-2), now: now, calendar: calendar) == .tooOld)
    }

    @Test func weekAgoIsTooOld() {
        #expect(ReviewDateCheck.status(for: day(-7), now: now, calendar: calendar) == .tooOld)
    }

    @Test func tomorrowIsFuture() {
        #expect(ReviewDateCheck.status(for: day(1), now: now, calendar: calendar) == .future)
    }

    @Test func nextWeekIsFuture() {
        #expect(ReviewDateCheck.status(for: day(7), now: now, calendar: calendar) == .future)
    }

    /// Day comparison ignores time component.
    @Test func lateHourSameDayStillToday() {
        let late = day(0, hour: 23)
        let early = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: now)!
        #expect(ReviewDateCheck.status(for: late, now: early, calendar: calendar) == .today)
    }

    @Test func warningFlagCoversTooOldAndFuture() {
        #expect(ReviewDateStatus.today.isWarning == false)
        #expect(ReviewDateStatus.yesterday.isWarning == false)
        #expect(ReviewDateStatus.tooOld.isWarning == true)
        #expect(ReviewDateStatus.future.isWarning == true)
    }
}
