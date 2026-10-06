import Foundation
import SwiftData

/// Decides whether adding an entry would disturb a month whose reconciliation came out balanced.
enum ReconciledMonthWarning {
    /// True when the entry falls in a closed month whose saved reconciliation shows no difference.
    static func shouldWarn(
        entryDate: Date,
        today: Date,
        summary: ReconciliationSummary,
        calendar: Calendar = .current
    ) -> Bool {
        let month = CategoryBudgetStore.monthKey(from: entryDate, calendar: calendar)
        guard month == summary.month else { return false }
        let status = ReconciliationSummary.periodStatus(month: month, today: today, calendar: calendar)
        guard status == .closed else { return false }
        // A remaining difference means the reconciliation is unfinished, so entries are expected.
        return summary.isReconciled(status: status) && summary.isBalanced
    }

    static func message(monthKey: Int) -> String {
        "\(monthKey / 100)년 \(monthKey % 100)월은 정산이 끝난 달이에요. 항목을 추가하면 정산 결과가 달라져요."
    }
}

/// Resolves the warning against the month's stored reconciliation rows and entries at save time.
@MainActor
enum ReconciledMonthGuard {
    /// Returns the warning text when the date's month is reconciled without a difference, otherwise nil.
    static func warningMessage(
        for date: Date,
        in context: ModelContext,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        let month = CategoryBudgetStore.monthKey(from: date, calendar: calendar)
        // Only a closed month can already be reconciled; skip the fetches for every other month.
        let status = ReconciliationSummary.periodStatus(month: month, today: today, calendar: calendar)
        guard status == .closed else { return nil }
        let monthStart = CategoryBudgetStore.date(from: month, calendar: calendar)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        let entryDescriptor = FetchDescriptor<SavedEntry>(
            predicate: #Predicate { $0.date >= monthStart && $0.date < monthEnd }
        )
        // The difference needs the month's saved entries; a failed read skips the warning.
        guard let input = try? ReconciliationStore().summaryInput(for: month, in: context),
              let entries = try? context.fetch(entryDescriptor) else { return nil }
        let summary = ReconciliationSummary.compute(
            entries: entries,
            input: input,
            targetMonth: month,
            calendar: calendar
        )
        guard ReconciledMonthWarning.shouldWarn(
            entryDate: date, today: today, summary: summary, calendar: calendar
        ) else { return nil }
        return ReconciledMonthWarning.message(monthKey: month)
    }
}
