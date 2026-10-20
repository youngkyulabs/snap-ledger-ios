// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct HistoryCalendarTests {
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
            csvFile: "expenses-\(y)-\(m.zeroPadded(2)).csv"
        )
    }

    private typealias Day = HistoryCalendar.Day

    // MARK: - Cells

    @Test func cellsForOctober2026() {
        let cells = HistoryCalendar.cells(monthKey: 202610, calendar: kst)
        #expect(cells.count == 42)
        #expect(cells[0..<4].allSatisfy { $0 == nil })
        #expect(cells[4] == 1)
        #expect(cells[34] == 31)
        #expect(cells[35...].allSatisfy { $0 == nil })
    }

    @Test func cellsForSixWeekMonth() {
        let cells = HistoryCalendar.cells(monthKey: 202608, calendar: kst)
        #expect(cells.count == 42)
        #expect(cells[6] == 1)
        #expect(cells[36] == 31)
    }

    @Test func cellsStayOnSundayStart() {
        var mondayFirst = kst
        mondayFirst.firstWeekday = 2
        let cells = HistoryCalendar.cells(monthKey: 202610, calendar: mondayFirst)
        #expect(cells[4] == 1)
    }

    // MARK: - Daily totals

    @Test func dailyTotalsSumsPerDay() {
        let entries = [
            entry(2026, 10, 19, amount: 1000),
            entry(2026, 10, 19, amount: 2000),
            entry(2026, 10, 18, amount: 500),
            entry(2026, 9, 30, amount: 700),
        ]
        let totals = HistoryCalendar.dailyTotals(entries, monthKey: 202610, calendar: kst)
        #expect(totals == [19: 3000, 18: 500])
    }

    @Test func dailyTotalsUseCalendarDayBoundary() {
        let entries = [
            entry(2026, 10, 19, h: 23, amount: 100),
            entry(2026, 10, 20, h: 0, amount: 200),
        ]
        let totals = HistoryCalendar.dailyTotals(entries, monthKey: 202610, calendar: kst)
        #expect(totals == [19: 100, 20: 200])
    }

    @Test func zeroAmountDayIsRecorded() {
        let totals = HistoryCalendar.dailyTotals([entry(2026, 10, 5, amount: 0)], monthKey: 202610, calendar: kst)
        #expect(totals[5] == 0)
        let state = HistoryCalendar.state(
            of: Day(monthKey: 202610, day: 5),
            today: Day(monthKey: 202610, day: 20),
            hasEntries: true
        )
        #expect(state == .recorded)
    }

    // MARK: - Day state

    @Test func stateCoversEmptyAndFuture() {
        let today = Day(monthKey: 202610, day: 20)
        func state(_ key: Int, _ day: Int, _ has: Bool) -> HistoryCalendar.DayState {
            HistoryCalendar.state(of: Day(monthKey: key, day: day), today: today, hasEntries: has)
        }
        #expect(state(202610, 12, false) == .empty)
        #expect(state(202610, 20, false) == .empty)
        #expect(state(202610, 21, false) == .future)
        #expect(state(202611, 1, false) == .future)
        #expect(state(202609, 30, false) == .empty)
        #expect(state(202610, 25, true) == .recorded)
    }
}
