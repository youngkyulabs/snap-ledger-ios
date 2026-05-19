// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct HistoryGroupingTests {
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

    private func entry(_ y: Int, _ m: Int, _ d: Int, h: Int = 12,
                       merchant: String = "M", amount: Int = 100,
                       savedAt: Date? = nil) -> SavedEntry {
        SavedEntry(
            date: date(y, m, d, h),
            amount: amount,
            merchant: merchant,
            category: nil,
            savedAt: savedAt ?? date(y, m, d, h),
            csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv"
        )
    }

    @Test func emptyInputProducesNoGroups() {
        let out = HistoryGrouping.group(entries: [], calendar: kst)
        #expect(out.isEmpty)
    }

    @Test func sameDayItemsGrouped() {
        let entries = [
            entry(2026, 5, 17, merchant: "A", amount: 1000),
            entry(2026, 5, 17, merchant: "B", amount: 2000),
        ]
        let out = HistoryGrouping.group(entries: entries, calendar: kst)
        #expect(out.count == 1)
        #expect(out[0].days.count == 1)
        #expect(out[0].days[0].entries.count == 2)
        #expect(out[0].days[0].total == 3000)
    }

    @Test func monthBoundaryProducesTwoMonths() {
        let entries = [
            entry(2026, 4, 30, merchant: "A", amount: 100),
            entry(2026, 5, 1, merchant: "B", amount: 200),
        ]
        let out = HistoryGrouping.group(entries: entries, calendar: kst)
        #expect(out.count == 2)
        #expect(out[0].title.contains("5월"))
        #expect(out[1].title.contains("4월"))
    }

    @Test func daysWithinMonthAreSortedDescending() {
        let entries = [
            entry(2026, 5, 1, merchant: "A"),
            entry(2026, 5, 17, merchant: "B"),
            entry(2026, 5, 10, merchant: "C"),
        ]
        let out = HistoryGrouping.group(entries: entries, calendar: kst)
        let days = out[0].days
        #expect(days.count == 3)
        #expect(days[0].entries[0].merchant == "B")
        #expect(days[1].entries[0].merchant == "C")
        #expect(days[2].entries[0].merchant == "A")
    }

    @Test func sameDayEntriesSortedBySavedAtDescending() {
        let earlier = entry(2026, 5, 17, h: 9, merchant: "early",
                            savedAt: date(2026, 5, 17, 9))
        let later = entry(2026, 5, 17, h: 10, merchant: "late",
                          savedAt: date(2026, 5, 17, 20))
        let out = HistoryGrouping.group(entries: [earlier, later], calendar: kst)
        let dayEntries = out[0].days[0].entries
        #expect(dayEntries[0].merchant == "late")
        #expect(dayEntries[1].merchant == "early")
    }

    @Test func dayTitleIncludesKoreanWeekday() {
        let out = HistoryGrouping.group(entries: [entry(2026, 5, 17)], calendar: kst)
        let title = out[0].days[0].title
        #expect(title.contains("5월"))
        #expect(title.contains("17"))
        #expect(title.contains("일"))
    }

    @Test func monthTitleIsKoreanYearMonth() {
        let out = HistoryGrouping.group(entries: [entry(2026, 5, 17)], calendar: kst)
        #expect(out[0].title == "2026년 5월")
    }
}
