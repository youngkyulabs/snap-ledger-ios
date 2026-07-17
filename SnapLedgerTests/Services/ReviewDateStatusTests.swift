// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// `ReviewDateCheck.status` — 검토 화면 날짜가 오늘/어제/그저께 이하/미래 중 무엇인지.
/// 정상 범위는 오늘·어제, 그 밖(tooOld·future)은 경고(isWarning) 대상이다.
struct ReviewDateStatusTests {
    // 시드/테스트 관례: .current 캘린더 정오 기준 (고정 타임존이면 CI(UTC)만 실패).
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

    /// 시각은 무시하고 '일' 단위로만 비교한다 — 같은 날 늦은 시각도 오늘.
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
