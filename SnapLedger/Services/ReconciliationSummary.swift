import Foundation

struct ReconciliationSummary: Equatable {
    let month: Int
    let openingBalanceTotal: Int
    let closingBalanceTotal: Int
    let interestTotal: Int
    let salaryAmount: Int
    let creditCardAmount: Int
    let savingsAmount: Int
    let adjustmentNetAmount: Int
    let recordedExpenseAmount: Int
    let actualSpending: Int
    let recordedSpending: Int
    let difference: Int
    let hasReconciliationData: Bool

    var isBalanced: Bool { difference == 0 }

    static func compute(
        entries: [SavedEntry],
        reconciliation: MonthlyReconciliation?,
        balances: [AccountMonthlyBalance],
        adjustments: [CashAdjustment],
        targetMonth: Int,
        calendar: Calendar = .current
    ) -> ReconciliationSummary {
        let monthEntries = entries.filter {
            CategoryBudgetStore.monthKey(from: $0.date, calendar: calendar) == targetMonth
        }
        let monthBalances = balances.filter { $0.monthKey == targetMonth }
        let monthAdjustments = adjustments.filter { $0.monthKey == targetMonth }
        let monthReconciliation = reconciliation?.monthKey == targetMonth ? reconciliation : nil

        let opening = monthBalances.reduce(0) { $0 + $1.openingBalance }
        let closing = monthBalances.reduce(0) { $0 + $1.closingBalance }
        let interest = monthBalances.reduce(0) { $0 + $1.interestAmount }
        let salary = monthReconciliation?.salaryAmount ?? 0
        let card = monthReconciliation?.creditCardAmount ?? 0
        let savings = monthReconciliation?.savingsAmount ?? 0
        let adjustmentNet = monthAdjustments.reduce(0) { partial, adjustment in
            switch adjustment.direction {
            case .deposit:
                return partial + adjustment.amount
            case .withdrawal:
                return partial - adjustment.amount
            }
        }
        let recordedExpense = monthEntries.reduce(0) { $0 + $1.amount }
        let actual = opening + salary + interest + adjustmentNet + card - closing
        let recorded = recordedExpense + savings
        let hasData = monthReconciliation != nil || !monthBalances.isEmpty || !monthAdjustments.isEmpty

        return ReconciliationSummary(
            month: targetMonth,
            openingBalanceTotal: opening,
            closingBalanceTotal: closing,
            interestTotal: interest,
            salaryAmount: salary,
            creditCardAmount: card,
            savingsAmount: savings,
            adjustmentNetAmount: adjustmentNet,
            recordedExpenseAmount: recordedExpense,
            actualSpending: actual,
            recordedSpending: recorded,
            difference: actual - recorded,
            hasReconciliationData: hasData
        )
    }
}
