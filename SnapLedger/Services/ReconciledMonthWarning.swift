import Foundation
import SwiftData

/// Decides whether adding an entry would disturb a month whose reconciliation is already concluded.
enum ReconciledMonthWarning {
    /// True when the entry falls in a closed month that carries saved reconciliation data.
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
        return summary.isReconciled(status: status)
    }

    static func message(monthKey: Int) -> String {
        "\(monthKey / 100)년 \(monthKey % 100)월은 정산이 끝난 달이에요. 항목을 추가하면 정산 결과가 달라져요."
    }
}

/// Resolves the warning against stored reconciliation rows at save time.
@MainActor
enum ReconciledMonthGuard {
    /// Returns the warning text when the date's month is already reconciled, otherwise nil.
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
        // `isReconciled` reads only reconciliation rows, so saved entries are not needed here.
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationStore().summaryInput(for: month, in: context),
            targetMonth: month,
            calendar: calendar
        )
        guard ReconciledMonthWarning.shouldWarn(
            entryDate: date, today: today, summary: summary, calendar: calendar
        ) else { return nil }
        return ReconciledMonthWarning.message(monthKey: month)
    }
}
