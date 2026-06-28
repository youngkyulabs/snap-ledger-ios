import Foundation
import SwiftData

enum BudgetProgress {
    enum State: Equatable { case under, near, over }

    struct Line: Identifiable, Equatable {
        let category: String
        let spent: Int
        let limit: Int      // > 0 보장 (resolveLimit이 0/nil을 제외)
        let state: State
        var remaining: Int { limit - spent }          // 음수면 초과
        var ratio: Double { limit > 0 ? Double(spent) / Double(limit) : 0 }
        var id: String { category }
    }

    struct Unbudgeted: Identifiable, Equatable {
        let category: String    // 미분류 포함
        let spent: Int
        var id: String { category }
    }

    struct Summary: Equatable {
        let month: Int
        let totalSpent: Int
        let totalLimit: Int
        let budgetedSpent: Int
        let unbudgetedSpent: Int
        let lines: [Line]
        let unbudgeted: [Unbudgeted]
        let overallState: State
        var overallRatio: Double { totalLimit > 0 ? Double(totalSpent) / Double(totalLimit) : 0 }
    }

    static func compute(
        entries: [SavedEntry],
        budgets: [CategoryBudget],
        targetMonth: Int,
        nearThreshold: Double = 0.8,
        calendar: Calendar = .current
    ) -> Summary {
        // 1. 그 달 카테고리별 지출 — 통계 집계 재사용(숫자 일관성).
        let months = StatisticsAggregation.aggregate(entries: entries, calendar: calendar)
        let monthStats = months.first { ($0.id.year ?? 0) * 100 + ($0.id.month ?? 0) == targetMonth }
        var spentByCategory: [String: Int] = [:]
        for slice in monthStats?.slices ?? [] {
            spentByCategory[slice.category] = slice.total
        }
        let totalSpent = monthStats?.total ?? 0

        // 2. 그 달 유효 한도가 있는 카테고리 → Line (현재 프리셋 비의존, 데이터 주도).
        var lines: [Line] = []
        for category in Set(budgets.map(\.category)) {
            guard let limit = CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: targetMonth) else {
                continue
            }
            let spent = spentByCategory[category] ?? 0
            let ratio = Double(spent) / Double(limit)
            let state: State = ratio >= 1.0 ? .over : (ratio >= nearThreshold ? .near : .under)
            lines.append(Line(category: category, spent: spent, limit: limit, state: state))
        }
        lines.sort { lhs, rhs in
            lhs.ratio != rhs.ratio ? lhs.ratio > rhs.ratio : lhs.category < rhs.category
        }

        // 3. 한도 없이 쓴 카테고리(미분류 포함).
        let budgeted = Set(lines.map(\.category))
        var unbudgeted: [Unbudgeted] = []
        for (category, spent) in spentByCategory where !budgeted.contains(category) {
            unbudgeted.append(Unbudgeted(category: category, spent: spent))
        }
        unbudgeted.sort { lhs, rhs in
            lhs.spent != rhs.spent ? lhs.spent > rhs.spent : lhs.category < rhs.category
        }

        // 4. 합계 + 전체 상태.
        let totalLimit = lines.reduce(0) { $0 + $1.limit }
        let budgetedSpent = lines.reduce(0) { $0 + $1.spent }
        let overallRatio = totalLimit > 0 ? Double(totalSpent) / Double(totalLimit) : 0
        let overallState: State = totalLimit == 0
            ? .under
            : (overallRatio >= 1.0 ? .over : (overallRatio >= nearThreshold ? .near : .under))

        return Summary(
            month: targetMonth,
            totalSpent: totalSpent,
            totalLimit: totalLimit,
            budgetedSpent: budgetedSpent,
            unbudgetedSpent: totalSpent - budgetedSpent,
            lines: lines,
            unbudgeted: unbudgeted,
            overallState: overallState
        )
    }

    /// 표시용 사용률(%). 한도를 넘기 전(ratio < 1)에는 반올림이 100%에 닿더라도 99%로 묶어
    /// "100% · N원 남음" 같은 모순 표기를 막는다. 도달·초과(ratio ≥ 1)는 그대로 보여준다.
    static func usagePercent(ratio: Double) -> Int {
        let raw = Int((ratio * 100).rounded())
        return ratio < 1.0 ? min(raw, 99) : raw
    }

    /// 저장 직후 그 항목이 그 달 예산 임계점(near/over)에 닿았는지. 한도가 없거나
    /// 아직 여유(under)면 nil — 검토 탭 상태 스트립을 띄울지 결정하는 단일 진입점.
    @MainActor
    static func thresholdLine(for entry: ParsedEntry, in context: ModelContext) -> Line? {
        guard let category = entry.category, !category.isEmpty else { return nil }
        let month = CategoryBudgetStore.monthKey(from: entry.date)
        guard let line = line(for: category, asOf: month, in: context),
              line.state != .under else { return nil }
        return line
    }

    /// 검토 탭 상태 스트립용: 그 달 해당 카테고리의 예산 라인. 한도(유효 monthlyLimit > 0)가 없으면 nil.
    /// compute를 재사용해 예산 탭과 숫자 일관성을 보장한다.
    @MainActor
    static func line(for category: String, asOf month: Int, in context: ModelContext) -> Line? {
        let calendar = Calendar.current
        // 대상 월·카테고리로 fetch를 좁혀 전체 집계를 피한다(compute는 targetMonth만 사용).
        guard let monthStart = calendar.date(from: DateComponents(year: month / 100, month: month % 100)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return nil
        }
        let entryDescriptor = FetchDescriptor<SavedEntry>(
            predicate: #Predicate { $0.date >= monthStart && $0.date < monthEnd }
        )
        let budgetDescriptor = FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []
        let budgets = (try? context.fetch(budgetDescriptor)) ?? []
        return compute(entries: entries, budgets: budgets, targetMonth: month, calendar: calendar)
            .lines.first { $0.category == category }
    }

    /// 상태 스트립 한 줄 요약: "식비 · 80% · 12,000원 남음" / 초과 시 "... · 120% · 3,000원 초과".
    static func statusSummary(for line: Line) -> String {
        let percent = usagePercent(ratio: line.ratio)
        let tail = line.remaining >= 0
            ? "\(line.remaining.formatted())원 남음"
            : "\((-line.remaining).formatted())원 초과"
        return "\(line.category) · \(percent)% · \(tail)"
    }
}
