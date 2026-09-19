// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Trend window placement relative to the month selected in the ledger.
@MainActor
struct TrendWindowAnchorTests {
    let kst: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        cal.locale = Locale(identifier: "ko_KR")
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        return kst.date(from: comps)!
    }

    private func entry(_ y: Int, _ m: Int, _ d: Int, amount: Int) -> SavedEntry {
        SavedEntry(
            date: date(y, m, d),
            amount: amount,
            merchant: "M",
            category: nil,
            savedAt: date(y, m, d),
            csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv"
        )
    }

    @Test func trendAnchorIsSelectedMonthWhenItIsTheCurrentMonth() {
        let anchor = StatisticsAggregation.trendAnchorKey(selected: 202609, current: 202609)
        #expect(anchor == 202609)
    }

    @Test func trendAnchorIsOneMonthAfterSelectedPastMonth() {
        let anchor = StatisticsAggregation.trendAnchorKey(selected: 202606, current: 202609)
        #expect(anchor == 202607)
    }

    @Test func trendAnchorRollsIntoNextYearForDecemberSelection() {
        let anchor = StatisticsAggregation.trendAnchorKey(selected: 202512, current: 202609)
        #expect(anchor == 202601)
    }

    @Test func trendAnchorNeverPassesTheCurrentMonth() {
        // Defensive: selection is bounded to the current month, but a future key must not widen the window.
        let anchor = StatisticsAggregation.trendAnchorKey(selected: 202612, current: 202609)
        #expect(anchor == 202609)
    }

    @Test func trendWindowEndsOneMonthAfterSelectedPastMonth() {
        let entries = [
            entry(2026, 2, 1, amount: 2000),
            entry(2026, 6, 1, amount: 6000),
            entry(2026, 7, 1, amount: 7000),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let anchorKey = StatisticsAggregation.trendAnchorKey(selected: 202606, current: 202609)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: CategoryBudgetStore.date(from: anchorKey, calendar: kst),
            calendar: kst,
            trimLeadingZeros: false
        )
        // Selecting 6월 while 9월 is current shows 2월...7월.
        #expect(trend.map { $0.id.month } == [2, 3, 4, 5, 6, 7])
        #expect(trend[0].total == 2000)
        #expect(trend[5].total == 7000)
    }
}
