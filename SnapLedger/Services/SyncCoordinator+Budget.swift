import Foundation
import SwiftData

@MainActor
extension SyncCoordinator {
    /// 주어진 달들의 예산 CSV를 앱 내용으로 다시 쓴다. 그 달 유효 한도가 없으면 파일을 제거한다.
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

    /// 백필 대상 달: 가장 이른 effectiveFrom부터 `current`까지 중, 유효 한도가 있는 달.
    /// forward-propagation(이월)으로 한도가 적용되는 달까지 포함한다.
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
