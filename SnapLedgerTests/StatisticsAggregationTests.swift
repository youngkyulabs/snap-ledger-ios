// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct StatisticsAggregationTests {
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

    private func entry(_ y: Int, _ m: Int, _ d: Int,
                       merchant: String = "M", amount: Int = 1000,
                       category: String? = nil) -> SavedEntry {
        SavedEntry(
            date: date(y, m, d),
            amount: amount,
            merchant: merchant,
            category: category,
            savedAt: date(y, m, d),
            csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv"
        )
    }

    @Test func emptyInputProducesNoStats() {
        let out = StatisticsAggregation.aggregate(entries: [], calendar: kst)
        #expect(out.isEmpty)
    }

    @Test func monthsSortedDescending() {
        let entries = [
            entry(2026, 3, 1),
            entry(2026, 5, 17),
            entry(2026, 4, 10),
        ]
        let out = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        #expect(out.count == 3)
        #expect(out[0].id.month == 5)
        #expect(out[1].id.month == 4)
        #expect(out[2].id.month == 3)
    }

    @Test func monthTotalAndShares() {
        let entries = [
            entry(2026, 5, 1, amount: 6000, category: "식비"),
            entry(2026, 5, 2, amount: 3000, category: "교통"),
            entry(2026, 5, 3, amount: 1000, category: "카페"),
        ]
        let out = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        #expect(out[0].total == 10_000)
        #expect(out[0].entryCount == 3)
        #expect(out[0].slices.first?.category == "식비")
        #expect(out[0].slices.first?.share == 0.6)
    }

    @Test func nilOrEmptyCategoryFoldsIntoUncategorized() {
        let entries = [
            entry(2026, 5, 1, amount: 1000, category: nil),
            entry(2026, 5, 2, amount: 2000, category: ""),
            entry(2026, 5, 3, amount: 500, category: "  "),
        ]
        let out = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        #expect(out[0].slices.count == 1)
        #expect(out[0].slices[0].category == "미분류")
        #expect(out[0].slices[0].total == 3500)
    }

    @Test func slicesSortedByTotalDescending() {
        let entries = [
            entry(2026, 5, 1, amount: 100, category: "C"),
            entry(2026, 5, 2, amount: 500, category: "A"),
            entry(2026, 5, 3, amount: 300, category: "B"),
        ]
        let out = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let cats = out[0].slices.map(\.category)
        #expect(cats == ["A", "B", "C"])
    }

    @Test func csvFilenameMatchesMonth() {
        let entries = [entry(2026, 5, 17)]
        let out = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        #expect(out[0].csvFilename == "expenses-2026-05.csv")
    }

    @Test func trendFillsEmptyMonthsWithZero() {
        let trend = StatisticsAggregation.trend(
            months: [],
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        #expect(trend.count == 6)
        #expect(trend.allSatisfy { $0.total == 0 })
        #expect(trend.first?.id.year == 2025)
        #expect(trend.first?.id.month == 12)
        #expect(trend.last?.id.year == 2026)
        #expect(trend.last?.id.month == 5)
    }

    @Test func trendComputesDeltaAndRatioWithExistingMonths() {
        let entries = [
            entry(2026, 3, 1, amount: 10_000),
            entry(2026, 4, 1, amount: 15_000),
            entry(2026, 5, 1, amount: 12_000),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        #expect(trend.count == 6)
        // [12-2025, 1-2026, 2-2026, 3-2026, 4-2026, 5-2026] = [0, 0, 0, 10000, 15000, 12000]
        #expect(trend[3].id.month == 3)
        #expect(trend[3].total == 10_000)
        #expect(trend[4].deltaFromPrevious == 5000)
        #expect(trend[4].ratioFromPrevious == 0.5)
        #expect(trend[5].deltaFromPrevious == -3000)
        #expect(abs((trend[5].ratioFromPrevious ?? 0) - (-0.2)) < 0.0001)
    }

    @Test func trendOrderedAscendingByMonth() {
        let entries = [
            entry(2026, 5, 1, amount: 100),
            entry(2026, 3, 1, amount: 100),
            entry(2026, 4, 1, amount: 100),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        let monthsInOrder = trend.map { $0.id.month }
        #expect(monthsInOrder == [12, 1, 2, 3, 4, 5])
    }

    @Test func trendCapsToLimitFromReferenceDate() {
        var entries: [SavedEntry] = []
        for month in 1...8 {
            entries.append(entry(2026, month, 1, amount: month * 1000))
        }
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 8, 1),
            calendar: kst
        )
        #expect(trend.count == 6)
        #expect(trend.first?.id.month == 3)
        #expect(trend.last?.id.month == 8)
        #expect(trend.first?.total == 3000)
        #expect(trend.last?.total == 8000)
    }

    @Test func trendRatioNilWhenPriorIsZero() {
        let entries = [entry(2026, 5, 1, amount: 1000)]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        #expect(trend.last?.total == 1000)
        #expect(trend.last?.deltaFromPrevious == 1000)
        #expect(trend.last?.ratioFromPrevious == nil)
    }
}
