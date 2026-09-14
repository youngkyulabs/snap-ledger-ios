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

    @Test func trendReturnsEmptyWhenAllSlotsAreZero() {
        let trend = StatisticsAggregation.trend(
            months: [],
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        #expect(trend.isEmpty)
    }

    @Test func trendWithoutTrimKeepsFullSixSlots() {
        let entries = [
            entry(2026, 3, 1, amount: 10_000),
            entry(2026, 5, 1, amount: 8_000),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst,
            trimLeadingZeros: false
        )
        // Chart retains leading zero months.
        #expect(trend.count == 6)
        #expect(trend.map { $0.id.month } == [12, 1, 2, 3, 4, 5])
        #expect(trend[0].total == 0)
        #expect(trend[3].total == 10_000)
        #expect(trend[5].total == 8_000)
    }

    @Test func trendTrimsLeadingZeroMonths() {
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
        // [12-2025, 1-2026, 2-2026, 3, 4, 5] = [0, 0, 0, 10000, 15000, 12000]
        // Leading 3 zero months are trimmed.
        #expect(trend.count == 3)
        #expect(trend[0].id.month == 3)
        #expect(trend[0].total == 10_000)
        // First slot after trimming resets delta to nil.
        #expect(trend[0].deltaFromPrevious == nil)
        #expect(trend[0].ratioFromPrevious == nil)
        #expect(trend[1].deltaFromPrevious == 5000)
        #expect(trend[1].ratioFromPrevious == 0.5)
        #expect(trend[2].deltaFromPrevious == -3000)
        #expect(abs((trend[2].ratioFromPrevious ?? 0) - (-0.2)) < 0.0001)
    }

    @Test func trendKeepsInteriorZeroMonths() {
        // Intermediate zero months are preserved.
        let entries = [
            entry(2026, 3, 1, amount: 10_000),
            entry(2026, 5, 1, amount: 8_000),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        #expect(trend.count == 3)
        #expect(trend.map { $0.id.month } == [3, 4, 5])
        #expect(trend[1].total == 0)
        #expect(trend[1].deltaFromPrevious == -10_000)
        #expect(trend[2].total == 8_000)
        #expect(trend[2].deltaFromPrevious == 8_000)
        // Ratio is nil when previous month spending was zero
        #expect(trend[2].ratioFromPrevious == nil)
    }

    @Test func trendKeepsFullWindowWhenAllMonthsHaveData() {
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
        // First slot in window has nil delta (base month).
        #expect(trend.first?.deltaFromPrevious == nil)
        #expect(trend.last?.total == 8000)
    }

    @Test func trendSingleMonthIsBaseline() {
        let entries = [entry(2026, 5, 1, amount: 1000)]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats,
            limit: 6,
            referenceDate: date(2026, 5, 1),
            calendar: kst
        )
        // Leading zero months trimmed, leaving single base month.
        #expect(trend.count == 1)
        #expect(trend[0].id.month == 5)
        #expect(trend[0].total == 1000)
        #expect(trend[0].deltaFromPrevious == nil)
        #expect(trend[0].ratioFromPrevious == nil)
    }

    @Test func colorIndexUsesPresetOrder() {
        let presets = ["식비", "카페", "교통"]
        #expect(StatisticsAggregation.colorIndex(for: "식비", presets: presets, paletteCount: 12) == 0)
        #expect(StatisticsAggregation.colorIndex(for: "카페", presets: presets, paletteCount: 12) == 1)
        #expect(StatisticsAggregation.colorIndex(for: "교통", presets: presets, paletteCount: 12) == 2)
    }

    @Test func colorIndexIsDeterministicForUnregisteredCategory() {
        // Off-preset categories produce stable color index across launches.
        let presets = ["식비", "카페"]
        let first = StatisticsAggregation.colorIndex(for: "학원", presets: presets, paletteCount: 12)
        let second = StatisticsAggregation.colorIndex(for: "학원", presets: presets, paletteCount: 12)
        #expect(first == second)
    }

    @Test func colorIndexAlwaysInPaletteBounds() {
        let presets = ["식비", "카페", "교통", "쇼핑"]
        let names = ["식비", "학원", "마사지", "취미용품", "병원", "", "🍕맛집"]
        for name in names {
            let index = StatisticsAggregation.colorIndex(for: name, presets: presets, paletteCount: 12)
            #expect((0..<12).contains(index))
        }
    }

    // MARK: - Category Display Name & Entry Filter

    @Test func displayCategoryNormalizesNilAndWhitespace() {
        #expect(StatisticsAggregation.displayCategory(for: nil) == "미분류")
        #expect(StatisticsAggregation.displayCategory(for: "") == "미분류")
        #expect(StatisticsAggregation.displayCategory(for: "  ") == "미분류")
        #expect(StatisticsAggregation.displayCategory(for: " 식비 ") == "식비")
    }

    @Test func filteredEntriesMatchMonthAndCategory() {
        let entries = [
            entry(2026, 5, 1, merchant: "A", category: "식비"),
            entry(2026, 5, 2, merchant: "B", category: " 식비 "),
            entry(2026, 5, 3, merchant: "C", category: "카페"),
            entry(2026, 4, 30, merchant: "D", category: "식비"),
        ]
        let out = StatisticsAggregation.filteredEntries(
            entries, category: "식비", monthKey: 202605, calendar: kst
        )
        #expect(out.map(\.merchant).sorted() == ["A", "B"])
    }

    @Test func filteredEntriesMatchUncategorized() {
        let entries = [
            entry(2026, 5, 1, merchant: "A", category: nil),
            entry(2026, 5, 2, merchant: "B", category: ""),
            entry(2026, 5, 3, merchant: "C", category: "식비"),
        ]
        let out = StatisticsAggregation.filteredEntries(
            entries, category: "미분류", monthKey: 202605, calendar: kst
        )
        #expect(out.map(\.merchant).sorted() == ["A", "B"])
    }

    // MARK: - Category Monthly Trends (Stacked Chart)

    @Test func categoryTrendEmitsPointsPerMonthAndCategory() {
        let entries = [
            entry(2026, 4, 1, amount: 3000, category: "식비"),
            entry(2026, 5, 1, amount: 5000, category: "식비"),
            entry(2026, 5, 2, amount: 2000, category: "카페"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let points = StatisticsAggregation.categoryTrend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst
        )
        // Zero-spending months do not create chart points.
        #expect(points.count == 3)
        #expect(points.filter { $0.monthID.month == 5 }.count == 2)
        let april = points.first { $0.monthID.month == 4 }
        #expect(april?.category == "식비")
        #expect(april?.total == 3000)
        #expect(april?.shortTitle == "4월")
    }

    @Test func categoryTrendOrdersMonthsChronologicallyAndCategoriesByWindowTotal() {
        let entries = [
            entry(2026, 4, 1, amount: 1000, category: "카페"),
            entry(2026, 4, 2, amount: 900, category: "식비"),
            entry(2026, 5, 1, amount: 5000, category: "식비"),
            entry(2026, 5, 2, amount: 200, category: "카페"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let points = StatisticsAggregation.categoryTrend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst
        )
        // Stack order determined by total window spending descending.
        #expect(points.map { $0.monthID.month } == [4, 4, 5, 5])
        #expect(points.map(\.category) == ["식비", "카페", "식비", "카페"])
    }

    @Test func categoryTrendLimitsToWindow() throws {
        let entries = [
            entry(2025, 11, 1, amount: 1000, category: "식비"),
            entry(2026, 5, 1, amount: 2000, category: "식비"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let points = StatisticsAggregation.categoryTrend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst
        )
        // Months outside trend window are excluded.
        #expect(points.count == 1)
        let only = try #require(points.first)
        #expect(only.monthID.year == 2026)
        #expect(only.monthID.month == 5)
    }

    @Test func trendCategoriesOrderedByWindowTotalThenName() {
        let entries = [
            entry(2026, 4, 1, amount: 1000, category: "카페"),
            entry(2026, 4, 2, amount: 5900, category: "식비"),
            entry(2026, 5, 1, amount: 200, category: "카페"),
            entry(2026, 5, 2, amount: 1200, category: "교통"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let points = StatisticsAggregation.categoryTrend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst
        )
        // Ties resolved alphabetically by category name.
        #expect(StatisticsAggregation.trendCategories(in: points) == ["식비", "교통", "카페"])
    }

    // MARK: - Single Category Trend

    @Test func trendWithCategoryUsesCategoryTotalsAndDelta() {
        let entries = [
            entry(2026, 3, 1, amount: 10_000, category: "식비"),
            entry(2026, 3, 2, amount: 4000, category: "카페"),
            entry(2026, 4, 1, amount: 6000, category: "식비"),
            entry(2026, 5, 1, amount: 9000, category: "카페"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst,
            category: "식비"
        )
        // Trailing zero months are preserved for single category trend.
        #expect(trend.map(\.total) == [10_000, 6000, 0])
        #expect(trend[0].deltaFromPrevious == nil)
        #expect(trend[1].deltaFromPrevious == -4000)
        #expect(trend[2].deltaFromPrevious == -6000)
    }

    @Test func trendWithCategoryTrimsLeadingZerosOfThatCategory() {
        let entries = [
            entry(2026, 3, 1, amount: 1000, category: "카페"),
            entry(2026, 4, 1, amount: 2000, category: "식비"),
        ]
        let stats = StatisticsAggregation.aggregate(entries: entries, calendar: kst)
        let trend = StatisticsAggregation.trend(
            months: stats, limit: 6, referenceDate: date(2026, 5, 1), calendar: kst,
            category: "식비"
        )
        // Single category trend starts from first non-zero month.
        #expect(trend.map(\.total) == [2000, 0])
        #expect(trend[0].deltaFromPrevious == nil)
    }
}
