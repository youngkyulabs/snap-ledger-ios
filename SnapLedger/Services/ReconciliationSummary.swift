import Foundation

struct ReconciliationSummaryInput {
    var reconciliation: MonthlyReconciliation?
    var balances: [AccountMonthlyBalance]
    var adjustments: [CashAdjustment]
    var savingsItems: [SavingsItem]

    init(
        reconciliation: MonthlyReconciliation? = nil,
        balances: [AccountMonthlyBalance] = [],
        adjustments: [CashAdjustment] = [],
        savingsItems: [SavingsItem] = []
    ) {
        self.reconciliation = reconciliation
        self.balances = balances
        self.adjustments = adjustments
        self.savingsItems = savingsItems
    }
}

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
        input: ReconciliationSummaryInput,
        targetMonth: Int,
        calendar: Calendar = .current
    ) -> ReconciliationSummary {
        let monthEntries = entries.filter {
            CategoryBudgetStore.monthKey(from: $0.date, calendar: calendar) == targetMonth
        }
        let monthBalances = input.balances.filter { $0.monthKey == targetMonth }
        let monthAdjustments = input.adjustments.filter { $0.monthKey == targetMonth }
        let monthSavings = input.savingsItems.filter { $0.monthKey == targetMonth }
        let monthReconciliation = input.reconciliation?.monthKey == targetMonth ? input.reconciliation : nil

        let opening = monthBalances.reduce(0) { $0 + $1.openingBalance }
        let closing = monthBalances.reduce(0) { $0 + $1.closingBalance }
        let interest = monthBalances.reduce(0) { $0 + $1.interestAmount }
        let salary = monthReconciliation?.salaryAmount ?? 0
        let card = monthReconciliation?.creditCardAmount ?? 0
        let savings = monthSavings.reduce(0) { $0 + $1.amount }
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
        let hasData = monthReconciliation != nil || !monthBalances.isEmpty
            || !monthAdjustments.isEmpty || !monthSavings.isEmpty

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
