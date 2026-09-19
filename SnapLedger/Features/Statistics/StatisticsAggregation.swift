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

    /// Stacked trend chart data point for (month, category).
    struct CategoryTrendPoint: Identifiable, Equatable {
        let monthID: DateComponents
        let shortTitle: String
        let category: String
        let total: Int

        var id: String { "\(monthID.year ?? 0)-\(monthID.month ?? 0)-\(category)" }
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

    /// Newest month of the trend window for a selected month.
    /// The selected month sits last when it is the current month, and second to last
    /// otherwise so that the month right after it stays visible for context.
    static func trendAnchorKey(selected: Int, current: Int) -> Int {
        guard selected < current else { return current }
        return CategoryBudgetStore.nextMonthKey(selected)
    }

    static func trend(
        months: [MonthlyStats],
        limit: Int = 6,
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ko_KR"),
        trimLeadingZeros: Bool = true,
        category: String? = nil
    ) -> [TrendPoint] {
        guard limit > 0 else { return [] }

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.locale = locale
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.dateFormat = "M월"

        guard let slots = windowSlots(limit: limit, referenceDate: referenceDate, calendar: calendar) else {
            return []
        }
        let monthsByKey = monthsByLookupKey(months)

        var previous: Int?
        let raw: [TrendPoint] = slots.map { slot in
            let matched = monthsByKey[slot.lookupKey]
            let total: Int
            if let category {
                total = matched?.slices.first { $0.category == category }?.total ?? 0
            } else {
                total = matched?.total ?? 0
            }
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

        guard trimLeadingZeros else { return raw }

        // Trim leading empty months while preserving intermediate zero months.
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

    /// Month intervals for trend window ordered from oldest to newest.
    private static func windowSlots(
        limit: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> [(lookupKey: Int, date: Date)]? {
        guard limit > 0 else { return nil }
        let refComps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let refMonthStart = calendar.date(from: refComps) else { return nil }

        var slots: [(lookupKey: Int, date: Date)] = []
        for offset in stride(from: limit - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .month, value: -offset, to: refMonthStart) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: d)
            let lookupKey = (comps.year ?? 0) * 100 + (comps.month ?? 0)
            slots.append((lookupKey, d))
        }
        return slots
    }

    // Int key (year*100 + month) avoids DateComponents hash mismatches caused by
    // implicit timezone/calendar metadata returned by Calendar.dateComponents.
    private static func monthsByLookupKey(_ months: [MonthlyStats]) -> [Int: MonthlyStats] {
        var monthsByKey: [Int: MonthlyStats] = [:]
        for stats in months {
            let key = (stats.id.year ?? 0) * 100 + (stats.id.month ?? 0)
            monthsByKey[key] = stats
        }
        return monthsByKey
    }

    private static func slices(for items: [SavedEntry], monthTotal: Int) -> [CategorySlice] {
        var totals: [String: Int] = [:]
        for entry in items {
            let label = displayCategory(for: entry.category)
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

    /// Display category label, defaulting to uncategorized if empty.
    static func displayCategory(for category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uncategorizedLabel : trimmed
    }

    /// Filters entries matching the specified month and category.
    static func filteredEntries(
        _ entries: [SavedEntry],
        category: String,
        monthKey: Int,
        calendar: Calendar = .current
    ) -> [SavedEntry] {
        entries.filter {
            CategoryBudgetStore.monthKey(from: $0.date, calendar: calendar) == monthKey
                && displayCategory(for: $0.category) == category
        }
    }

    /// Computes stacked trend chart data points within the window.
    static func categoryTrend(
        months: [MonthlyStats],
        limit: Int = 6,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [CategoryTrendPoint] {
        guard let slots = windowSlots(limit: limit, referenceDate: referenceDate, calendar: calendar) else {
            return []
        }
        let monthsByKey = monthsByLookupKey(months)

        var windowTotals: [String: Int] = [:]
        for slot in slots {
            for slice in monthsByKey[slot.lookupKey]?.slices ?? [] {
                windowTotals[slice.category, default: 0] += slice.total
            }
        }
        let order = categoryOrder(windowTotals)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        var points: [CategoryTrendPoint] = []
        for slot in slots {
            guard let stats = monthsByKey[slot.lookupKey] else { continue }
            var idComps = DateComponents()
            idComps.year = slot.lookupKey / 100
            idComps.month = slot.lookupKey % 100
            let sorted = stats.slices.sorted { (rank[$0.category] ?? .max) < (rank[$1.category] ?? .max) }
            for slice in sorted {
                points.append(
                    CategoryTrendPoint(
                        monthID: idComps,
                        shortTitle: stats.shortTitle,
                        category: slice.category,
                        total: slice.total
                    )
                )
            }
        }
        return points
    }

    /// Categories ordered by total window spending descending.
    static func trendCategories(in points: [CategoryTrendPoint]) -> [String] {
        var totals: [String: Int] = [:]
        for point in points {
            totals[point.category, default: 0] += point.total
        }
        return categoryOrder(totals)
    }

    private static func categoryOrder(_ totals: [String: Int]) -> [String] {
        totals
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }

    /// Computes deterministic color palette index (0..<paletteCount) for a category.
    /// Presets use their index order; off-list categories fallback to djb2 hash for stability across launches.
    static func colorIndex(for category: String, presets: [String], paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        if let preset = presets.firstIndex(of: category) {
            return preset % paletteCount
        }
        return (presets.count + stableBucket(category, modulo: paletteCount)) % paletteCount
    }

    private static func stableBucket(_ string: String, modulo: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(modulo))
    }
}
