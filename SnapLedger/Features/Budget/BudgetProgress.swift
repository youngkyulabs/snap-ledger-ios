import Foundation
import SwiftData

enum BudgetProgress {
    enum State: Equatable { case under, near, over }

    struct Line: Identifiable, Equatable {
        let category: String
        let spent: Int
        let limit: Int      // Guaranteed > 0
        let state: State
        var remaining: Int { limit - spent }          // Negative indicates over budget
        var ratio: Double { limit > 0 ? Double(spent) / Double(limit) : 0 }
        var id: String { category }
    }

    struct Unbudgeted: Identifiable, Equatable {
        let category: String    // Includes uncategorized
        let spent: Int
        var id: String { category }
    }

    struct Summary: Equatable {
        let month: Int
        let totalSpent: Int
        let entryCount: Int
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
        // 1. Monthly spending per category.
        let months = StatisticsAggregation.aggregate(entries: entries, calendar: calendar)
        let monthStats = months.first { ($0.id.year ?? 0) * 100 + ($0.id.month ?? 0) == targetMonth }
        var spentByCategory: [String: Int] = [:]
        for slice in monthStats?.slices ?? [] {
            spentByCategory[slice.category] = slice.total
        }
        let totalSpent = monthStats?.total ?? 0
        let entryCount = monthStats?.entryCount ?? 0

        // 2. Categories with active budget limits.
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

        // 3. Categories spent without budget limits.
        let budgeted = Set(lines.map(\.category))
        var unbudgeted: [Unbudgeted] = []
        for (category, spent) in spentByCategory where !budgeted.contains(category) {
            unbudgeted.append(Unbudgeted(category: category, spent: spent))
        }
        unbudgeted.sort { lhs, rhs in
            lhs.spent != rhs.spent ? lhs.spent > rhs.spent : lhs.category < rhs.category
        }

        // 4. Totals and overall budget status.
        let totalLimit = lines.reduce(0) { $0 + $1.limit }
        let budgetedSpent = lines.reduce(0) { $0 + $1.spent }
        let overallRatio = totalLimit > 0 ? Double(totalSpent) / Double(totalLimit) : 0
        let overallState: State = totalLimit == 0
            ? .under
            : (overallRatio >= 1.0 ? .over : (overallRatio >= nearThreshold ? .near : .under))

        return Summary(
            month: targetMonth,
            totalSpent: totalSpent,
            entryCount: entryCount,
            totalLimit: totalLimit,
            budgetedSpent: budgetedSpent,
            unbudgetedSpent: totalSpent - budgetedSpent,
            lines: lines,
            unbudgeted: unbudgeted,
            overallState: overallState
        )
    }

    /// Formatted usage percentage, capping pre-limit ratios at 99%.
    static func usagePercent(ratio: Double) -> Int {
        let raw = Int((ratio * 100).rounded())
        return ratio < 1.0 ? min(raw, 99) : raw
    }

    /// Checks whether entry reached near/over threshold for toast.
    @MainActor
    static func thresholdLine(for entry: ParsedEntry, in context: ModelContext) -> Line? {
        guard let category = entry.category, !category.isEmpty else { return nil }
        let month = CategoryBudgetStore.monthKey(from: entry.date)
        guard let line = line(for: category, asOf: month, in: context),
              line.state != .under else { return nil }
        return line
    }

    /// Resolves budget progress line for review toast.
    @MainActor
    static func line(for category: String, asOf month: Int, in context: ModelContext) -> Line? {
        let calendar = Calendar.current
        // Narrow query by target month and category.
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

    /// Formats remaining or exceeded budget text.
    static func remainderText(for line: Line) -> String {
        line.remaining >= 0
            ? "\(line.remaining.formatted())원 남음"
            : "\((-line.remaining).formatted())원 초과"
    }

    /// Formats summary accessibility label for toast.
    static func toastSummary(for line: Line) -> String {
        "\(line.category) · \(usagePercent(ratio: line.ratio))% · \(remainderText(for: line))"
    }
}
