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

    /// 스택 추세 차트용 — (달, 카테고리)마다 한 포인트.
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

    /// 추세 윈도의 (lookupKey, 슬롯 시작일) 목록 — 오래된 달부터.
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

    /// 항목의 표시용 카테고리 이름 (nil·빈 값은 "미분류"). 슬라이스·필터가 같은 규칙을 쓴다.
    static func displayCategory(for category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uncategorizedLabel : trimmed
    }

    /// 카테고리 상세 시트용 — 해당 달(YYYYMM 키)·카테고리의 항목만 추린다.
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

    /// 스택 추세 차트용 — 윈도 안의 (달, 카테고리)별 합계 포인트. 기록 없는 달은
    /// 포인트를 만들지 않는다 (x축 라벨은 호출부가 도메인으로 고정).
    /// 막대 안 스택 순서가 달마다 흔들리지 않게, 달 안에서는 윈도 합계 내림차순으로 늘어놓는다.
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

    /// 추세 필터 메뉴용 — 윈도 합계 내림차순(동률은 이름순) 카테고리 목록.
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

    /// 카테고리에 매길 색 팔레트 인덱스(0..<paletteCount)를 정한다.
    /// presets 에 등록된 카테고리는 그 순서(인덱스)로 — 같은 카테고리는 항상 같은 색이면서
    /// 등록 순서가 다르면 색도 퍼진다. 등록 안 된 카테고리(가져온 CSV의 임의 카테고리,
    /// 학습된 가맹점 카테고리 등)는 이름의 결정적 해시로 fallback 한다.
    ///
    /// `String.hashValue` 는 쓰지 않는다 — Swift 는 해시 DoS 방어로 프로세스 실행마다
    /// 랜덤 시드를 적용해, 같은 이름이라도 앱을 재시작할 때마다 값이 바뀐다. 그러면
    /// presets 에 없는 카테고리의 색이 실행마다 달라진다. UTF8 바이트 기반 djb2 해시는
    /// 프로세스 간 안정적이라 색이 고정된다.
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
