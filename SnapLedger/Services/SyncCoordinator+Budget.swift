import Foundation
import SwiftData

@MainActor
extension SyncCoordinator {
    /// Rewrites budget CSV files for the given months, removing a file when that month has no effective limit.
    func exportBudgetMonths(_ keys: [String], folderURL: URL, in context: ModelContext) throws {
        let writer = BudgetCSVWriter(folder: folderURL)
        let budgets = (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        let presets = (try? context.fetch(FetchDescriptor<AppSettings>()))?
            .first?.categoryPresets ?? AppSettings.defaultPresets
        for key in keys {
            let rows = CategoryBudgetStore.resolveAll(
                in: budgets,
                asOf: Self.intMonthKey(from: key),
                presets: presets
            )
            try writer.replaceMonth(monthKey: key, rows: rows)
        }
    }

    /// Computes all month keys that have active budget limits.
    func budgetMonthKeys(
        asOf current: Int = CategoryBudgetStore.monthKey(from: Date()),
        in context: ModelContext
    ) -> Set<String> {
        let budgets = (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        guard let earliest = budgets.map({ $0.effectiveFrom }).min() else { return [] }
        let presets = (try? context.fetch(FetchDescriptor<AppSettings>()))?
            .first?.categoryPresets ?? AppSettings.defaultPresets
        var keys: Set<String> = []
        var month = earliest
        while month <= current {
            if !CategoryBudgetStore.resolveAll(in: budgets, asOf: month, presets: presets).isEmpty {
                keys.insert(Self.monthKeyString(from: month))
            }
            month = CategoryBudgetStore.nextMonthKey(month)
        }
        return keys
    }
}
