import Foundation

enum StatisticsAggregation {
    static let uncategorizedLabel = "미분류"

    struct CategorySlice: Identifiable, Equatable {
        let category: String
        let total: Int
        let share: Double

        var id: String { category }
    }

    struct MonthlyStats: Identifiable, Equatable {
        let id: DateComponents
        let title: String
        let shortTitle: String
        let total: Int
        let entryCount: Int
        let slices: [CategorySlice]
        let csvFilename: String
    }

    struct TrendPoint: Identifiable, Equatable {
        let id: DateComponents
        let shortTitle: String
        let total: Int
        let deltaFromPrevious: Int?
        let ratioFromPrevious: Double?
    }

    static func aggregate(
        entries: [SavedEntry],
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ko_KR")
    ) -> [MonthlyStats] {
        guard !entries.isEmpty else { return [] }

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = locale
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "yyyy년 M월"

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.locale = locale
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.dateFormat = "M월"

        var buckets: [DateComponents: [SavedEntry]] = [:]
        for entry in entries {
            var key = DateComponents()
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            key.year = comps.year
            key.month = comps.month
            buckets[key, default: []].append(entry)
        }

        let stats: [MonthlyStats] = buckets.map { monthKey, items in
            let total = items.reduce(0) { $0 + $1.amount }
            let monthDate = calendar.date(from: monthKey) ?? Date()
            return MonthlyStats(
                id: monthKey,
                title: monthFormatter.string(from: monthDate),
                shortTitle: shortFormatter.string(from: monthDate),
                total: total,
                entryCount: items.count,
                slices: slices(for: items, monthTotal: total),
                csvFilename: String(format: "expenses-%04d-%02d.csv",
                                    monthKey.year ?? 0,
                                    monthKey.month ?? 0)
            )
        }

        return stats.sorted { lhs, rhs in
            let l = (lhs.id.year ?? 0) * 100 + (lhs.id.month ?? 0)
            let r = (rhs.id.year ?? 0) * 100 + (rhs.id.month ?? 0)
            return l > r
        }
    }

    static func trend(
        months: [MonthlyStats],
        limit: Int = 6,
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ko_KR")
    ) -> [TrendPoint] {
        guard limit > 0 else { return [] }

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.locale = locale
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.dateFormat = "M월"

        let refComps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let refMonthStart = calendar.date(from: refComps) else { return [] }

        // Int key (year*100 + month) avoids DateComponents hash mismatches caused by
        // implicit timezone/calendar metadata returned by Calendar.dateComponents.
        var monthsByKey: [Int: MonthlyStats] = [:]
        for stats in months {
            let key = (stats.id.year ?? 0) * 100 + (stats.id.month ?? 0)
            monthsByKey[key] = stats
        }

        var slots: [(lookupKey: Int, date: Date)] = []
        for offset in stride(from: limit - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .month, value: -offset, to: refMonthStart) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: d)
            let lookupKey = (comps.year ?? 0) * 100 + (comps.month ?? 0)
            slots.append((lookupKey, d))
        }

        var previous: Int?
        let raw: [TrendPoint] = slots.map { slot in
            let matched = monthsByKey[slot.lookupKey]
            let total = matched?.total ?? 0
            let delta: Int? = previous.map { total - $0 }
            let ratio: Double? = {
                guard let prev = previous, prev > 0 else { return nil }
                return Double(total - prev) / Double(prev)
            }()
            previous = total
            var idComps = DateComponents()
            idComps.year = slot.lookupKey / 100
            idComps.month = slot.lookupKey % 100
            return TrendPoint(
                id: idComps,
                shortTitle: matched?.shortTitle ?? shortFormatter.string(from: slot.date),
                total: total,
                deltaFromPrevious: delta,
                ratioFromPrevious: ratio
            )
        }

        // 앞쪽의 0 슬롯(아직 기록이 없던 달)은 잘라낸다. 중간에 끼인 0은
        // "이 달은 기록을 안 했다"는 사실을 보여주기 위해 유지한다.
        // 트림 후의 첫 슬롯은 직전 0 슬롯과 비교한 delta가 의미 없으므로
        // "기준 월"로 리셋한다.
        let trimmed = Array(raw.drop { $0.total == 0 })
        guard let first = trimmed.first else { return [] }
        let resetFirst = TrendPoint(
            id: first.id,
            shortTitle: first.shortTitle,
            total: first.total,
            deltaFromPrevious: nil,
            ratioFromPrevious: nil
        )
        return [resetFirst] + trimmed.dropFirst()
    }

    private static func slices(for items: [SavedEntry], monthTotal: Int) -> [CategorySlice] {
        var totals: [String: Int] = [:]
        for entry in items {
            let label = normalize(category: entry.category)
            totals[label, default: 0] += entry.amount
        }
        let denominator = max(monthTotal, 1)
        return totals
            .map { key, value in
                CategorySlice(
                    category: key,
                    total: value,
                    share: Double(value) / Double(denominator)
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.category < rhs.category
            }
    }

    private static func normalize(category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uncategorizedLabel : trimmed
    }
}
