import Foundation

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
}
