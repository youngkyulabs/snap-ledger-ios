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

    static func today(_ now: Date = .now, calendar: Calendar = .current) -> Day {
        day(of: now, calendar: calendar)
    }

    /// Today when it has entries, else the latest recorded day before today; nil when none.
    static func initialSelection(_ entries: [SavedEntry], today: Day, calendar: Calendar = .current) -> Day? {
        entries
            .map { day(of: $0.date, calendar: calendar) }
            .filter { ($0.monthKey, $0.day) <= (today.monthKey, today.day) }
            .max { ($0.monthKey, $0.day) < ($1.monthKey, $1.day) }
    }

    /// Newest first: earliest entry month … max(today's month, latest entry month); [today's month] when empty.
    static func monthRange(_ entries: [SavedEntry], today: Day, calendar: Calendar = .current) -> [Int] {
        let keys = entries.map { CategoryBudgetStore.monthKey(from: $0.date, calendar: calendar) }
        let first = min(keys.min() ?? today.monthKey, today.monthKey)
        let last = max(keys.max() ?? today.monthKey, today.monthKey)
        var range = [first]
        while let current = range.last, current < last {
            range.append(CategoryBudgetStore.nextMonthKey(current))
        }
        return range.reversed()
    }

    /// Entries on that day, savedAt descending.
    static func entries(on day: Day, from entries: [SavedEntry], calendar: Calendar = .current) -> [SavedEntry] {
        entries
            .filter { self.day(of: $0.date, calendar: calendar) == day }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// VoiceOver label for a day cell; total is nil when the day has no entries.
    static func accessibilityLabel(for day: Day, total: Int?, isToday: Bool) -> String {
        var parts = ["\(day.monthKey % 100)월 \(day.day)일"]
        if isToday { parts.append("오늘") }
        parts.append(total.map { "\($0.formatted(.number))원" } ?? "기록 없음")
        return parts.joined(separator: ", ")
    }

    static func csvFilename(monthKey: Int) -> String {
        "expenses-\((monthKey / 100).zeroPadded(4))-\((monthKey % 100).zeroPadded(2)).csv"
    }

    private static func day(of date: Date, calendar: Calendar) -> Day {
        Day(
            monthKey: CategoryBudgetStore.monthKey(from: date, calendar: calendar),
            day: calendar.component(.day, from: date)
        )
    }
}
