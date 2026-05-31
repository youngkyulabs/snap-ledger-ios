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
        // 차트용 호출. 앞쪽 0도 그대로 살아있다.
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
        // 앞 3개월(12·1·2)은 트림되어 3·4·5월만 남는다.
        #expect(trend.count == 3)
        #expect(trend[0].id.month == 3)
        #expect(trend[0].total == 10_000)
        // 트림 후 첫 슬롯은 직전 비교가 무의미하므로 기준 월로 리셋된다.
        #expect(trend[0].deltaFromPrevious == nil)
        #expect(trend[0].ratioFromPrevious == nil)
        #expect(trend[1].deltaFromPrevious == 5000)
        #expect(trend[1].ratioFromPrevious == 0.5)
        #expect(trend[2].deltaFromPrevious == -3000)
        #expect(abs((trend[2].ratioFromPrevious ?? 0) - (-0.2)) < 0.0001)
    }

    @Test func trendKeepsInteriorZeroMonths() {
        // 3월 데이터, 4월 기록 없음, 5월 데이터 → 4월의 0은 트림되지 않고 유지된다.
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
        // 직전이 0이면 ratio는 nil
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
        // 윈도 첫 슬롯이지만 데이터가 있으므로 트림 없음. 그래도 트림 후 첫 슬롯
        // 처리 규칙에 따라 delta는 nil(기준 월).
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
        // 앞 5개월(0)은 모두 트림되어 5월만 남고, 기준 월로 표시된다.
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
        // presets 에 없는 카테고리도 같은 이름이면 항상 같은 인덱스 — String.hashValue 와 달리
        // 호출/실행 간 흔들리지 않아야 한다 (앱 재시작마다 색이 바뀌던 버그의 회귀 방지).
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
}
