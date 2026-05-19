import Foundation

enum HistoryGrouping {
    struct DayGroup: Identifiable {
        let id: DateComponents
        let title: String
        let total: Int
        let entries: [SavedEntry]
    }

    struct MonthGroup: Identifiable {
        let id: DateComponents
        let title: String
        let total: Int
        let days: [DayGroup]

        var csvFilename: String {
            String(format: "expenses-%04d-%02d.csv", id.year ?? 0, id.month ?? 0)
        }
    }

    static func group(
        entries: [SavedEntry],
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ko_KR")
    ) -> [MonthGroup] {
        guard !entries.isEmpty else { return [] }

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = locale
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "yyyy년 M월"

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = locale
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "M월 d일 (E)"

        var buckets: [DateComponents: [SavedEntry]] = [:]
        for entry in entries {
            let key = calendar.dateComponents([.year, .month, .day], from: entry.date)
            buckets[key, default: []].append(entry)
        }

        var daysByMonth: [DateComponents: [DayGroup]] = [:]
        for (dayKey, items) in buckets {
            let sorted = items.sorted { $0.savedAt > $1.savedAt }
            let dayDate = calendar.date(from: dayKey) ?? sorted[0].date
            let total = sorted.reduce(0) { $0 + $1.amount }
            let dayGroup = DayGroup(
                id: dayKey,
                title: dayFormatter.string(from: dayDate),
                total: total,
                entries: sorted
            )
            var monthKey = DateComponents()
            monthKey.year = dayKey.year
            monthKey.month = dayKey.month
            daysByMonth[monthKey, default: []].append(dayGroup)
        }

        return daysByMonth
            .map { monthKey, days in
                let sortedDays = days.sorted { lhs, rhs in
                    (lhs.id.day ?? 0) > (rhs.id.day ?? 0)
                }
                let monthDate = calendar.date(from: monthKey) ?? Date()
                let monthTotal = sortedDays.reduce(0) { $0 + $1.total }
                return MonthGroup(
                    id: monthKey,
                    title: monthFormatter.string(from: monthDate),
                    total: monthTotal,
                    days: sortedDays
                )
            }
            .sorted { lhs, rhs in
                let l = (lhs.id.year ?? 0) * 100 + (lhs.id.month ?? 0)
                let r = (rhs.id.year ?? 0) * 100 + (rhs.id.month ?? 0)
                return l > r
            }
    }
}
