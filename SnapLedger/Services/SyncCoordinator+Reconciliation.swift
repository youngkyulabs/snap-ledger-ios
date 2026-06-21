import Foundation
import SwiftData

@MainActor
extension SyncCoordinator {
    func exportReconciliationMonths(_ keys: [String], folderURL: URL, in context: ModelContext) throws {
        let writer = ReconciliationCSVWriter(folder: folderURL)
        let store = ReconciliationStore()
        for key in keys {
            try writer.replaceMonth(monthKey: key, rows: store.rows(for: Self.intMonthKey(from: key), in: context))
        }
    }

    func reconciliationMonthKeys(in context: ModelContext) -> Set<String> {
        let reconciliationKeys = ((try? context.fetch(FetchDescriptor<MonthlyReconciliation>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let balanceKeys = ((try? context.fetch(FetchDescriptor<AccountMonthlyBalance>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let adjustmentKeys = ((try? context.fetch(FetchDescriptor<CashAdjustment>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let savingsKeys = ((try? context.fetch(FetchDescriptor<SavingsItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let cardKeys = ((try? context.fetch(FetchDescriptor<CardUsageItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let incomeKeys = ((try? context.fetch(FetchDescriptor<IncomeItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        return Set(reconciliationKeys + balanceKeys + adjustmentKeys + savingsKeys + cardKeys + incomeKeys)
    }
}
