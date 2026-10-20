import Foundation

/// Pure helpers behind the history calendar screen.
enum HistoryCalendar {
    struct Day: Hashable {
        let monthKey: Int
        let day: Int
    }

    enum DayState: Equatable {
        case recorded, empty, future
    }

    /// 42 slots, Sunday first; nil = outside the month.
    static func cells(monthKey: Int, calendar: Calendar = .current) -> [Int?] {
        let first = CategoryBudgetStore.date(from: monthKey, calendar: calendar)
        // Weekday 1 is always Sunday, independent of the calendar's firstWeekday.
        let offset = calendar.component(.weekday, from: first) - 1
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return (0..<42).map { index in
            let day = index - offset + 1
            return (1...dayCount).contains(day) ? day : nil
        }
    }

    /// day-of-month → total; a day with entries is present even when its total is 0.
    static func dailyTotals(_ entries: [SavedEntry], monthKey: Int, calendar: Calendar = .current) -> [Int: Int] {
        var totals: [Int: Int] = [:]
        for entry in entries where CategoryBudgetStore.monthKey(from: entry.date, calendar: calendar) == monthKey {
            totals[calendar.component(.day, from: entry.date), default: 0] += entry.amount
        }
        return totals
    }

    static func state(of day: Day, today: Day, hasEntries: Bool) -> DayState {
        if hasEntries { return .recorded }
        return (day.monthKey, day.day) > (today.monthKey, today.day) ? .future : .empty
    }
}
