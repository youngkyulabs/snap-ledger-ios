import Foundation

struct ReconciliationSummaryInput {
    var reconciliation: MonthlyReconciliation?
    var balances: [AccountMonthlyBalance]
    var adjustments: [CashAdjustment]
    var savingsItems: [SavingsItem]
    var cardItems: [CardUsageItem]
    var incomeItems: [IncomeItem]

    init(
        reconciliation: MonthlyReconciliation? = nil,
        balances: [AccountMonthlyBalance] = [],
        adjustments: [CashAdjustment] = [],
        savingsItems: [SavingsItem] = [],
        cardItems: [CardUsageItem] = [],
        incomeItems: [IncomeItem] = []
    ) {
        self.reconciliation = reconciliation
        self.balances = balances
        self.adjustments = adjustments
        self.savingsItems = savingsItems
        self.cardItems = cardItems
        self.incomeItems = incomeItems
    }
}

struct ReconciliationSummary: Equatable {
    let month: Int
    let openingBalanceTotal: Int
    let closingBalanceTotal: Int
    let interestTotal: Int
    let salaryAmount: Int
    let creditCardAmount: Int
    /// Prior month's card bills paid out of this month's accounts.
    let previousCardAmount: Int
    let savingsAmount: Int
    let adjustmentNetAmount: Int
    let recordedExpenseAmount: Int
    let actualSpending: Int
    let recordedSpending: Int
    let difference: Int
    let hasReconciliationData: Bool
    /// Whether the user entered real figures: any balance with opening != closing, or any non-zero card amount.
    let hasStartedReconciliation: Bool

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
        let monthCards = input.cardItems.filter { $0.monthKey == targetMonth }
        let monthIncomes = input.incomeItems.filter { $0.monthKey == targetMonth }
        let monthReconciliation = input.reconciliation?.monthKey == targetMonth ? input.reconciliation : nil

        let opening = monthBalances.reduce(0) { $0 + $1.openingBalance }
        let closing = monthBalances.reduce(0) { $0 + $1.closingBalance }
        let interest = monthBalances.reduce(0) { $0 + $1.interestAmount }
        // Sum amounts across items
        let salary = monthIncomes.reduce(0) { $0 + $1.amount }
        let card = monthCards.reduce(0) { $0 + $1.amount }
        let previousCard = monthCards.reduce(0) { $0 + $1.previousAmount }
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
        // Calculate actual spending (excluding savings)
        // The prior month's bill lowered the closing balance without being spending of this month.
        let actual = opening + salary + interest + adjustmentNet + card - closing - savings - previousCard
        let recorded = recordedExpense
        let hasData = monthReconciliation != nil || !monthBalances.isEmpty
            || !monthAdjustments.isEmpty || !monthSavings.isEmpty || !monthCards.isEmpty
            || !monthIncomes.isEmpty
        let started = monthBalances.contains { $0.openingBalance != $0.closingBalance }
            || monthCards.contains { $0.amount != 0 || $0.previousAmount != 0 }

        return ReconciliationSummary(
            month: targetMonth,
            openingBalanceTotal: opening,
            closingBalanceTotal: closing,
            interestTotal: interest,
            salaryAmount: salary,
            creditCardAmount: card,
            previousCardAmount: previousCard,
            savingsAmount: savings,
            adjustmentNetAmount: adjustmentNet,
            recordedExpenseAmount: recordedExpense,
            actualSpending: actual,
            recordedSpending: recorded,
            difference: actual - recorded,
            hasReconciliationData: hasData,
            hasStartedReconciliation: started
        )
    }
}

/// Lifecycle status of the target reconciliation month.
enum ReconciliationPeriodStatus: Equatable {
    case inProgress
    case closed
}

/// Presentation verdict for reconciliation results.
struct ReconciliationVerdict: Equatable {
    enum Tone: Equatable {
        case balanced
        case off
        case inProgress
    }

    let tone: Tone
    let headline: String
    let detail: String
}

extension ReconciliationSummary {
    static func periodStatus(month: Int, today: Date, calendar: Calendar = .current) -> ReconciliationPeriodStatus {
        let currentMonth = CategoryBudgetStore.monthKey(from: today, calendar: calendar)
        return month >= currentMonth ? .inProgress : .closed
    }

    /// Whether to display finalized reconciliation verdict.
    func isReconciled(status: ReconciliationPeriodStatus) -> Bool {
        switch status {
        case .closed:     return hasReconciliationData
        case .inProgress: return hasStartedReconciliation
        }
    }

    /// Determines headline, detail, and tone for the summary.
    func verdict(
        status: ReconciliationPeriodStatus,
        revealInProgressDifference: Bool = false
    ) -> ReconciliationVerdict {
        switch status {
        case .inProgress:
            if revealInProgressDifference && !isBalanced {
                return differenceVerdict(tone: .inProgress)
            }
            return ReconciliationVerdict(tone: .inProgress, headline: "진행 중", detail: "")
        case .closed:
            if isBalanced {
                return ReconciliationVerdict(tone: .balanced, headline: "정상", detail: "차이 없음")
            }
            return differenceVerdict(tone: .off)
        }
    }

    private func differenceVerdict(tone: ReconciliationVerdict.Tone) -> ReconciliationVerdict {
        ReconciliationVerdict(
            tone: tone,
            headline: "\(abs(difference).formatted(.number))원 차이",
            detail: difference > 0 ? "실제 쓴 돈이 더 커요" : "기록한 돈이 더 커요"
        )
    }
}

extension ReconciliationVerdict {
    /// Default verdict when no reconciliation data exists.
    static let notReconciled = ReconciliationVerdict(tone: .inProgress, headline: "아직 정산 전", detail: "")
}

extension ReconciliationSummary {
    /// Returns user-facing reconciliation verdict for display.
    func displayVerdict(
        status: ReconciliationPeriodStatus,
        isReconciled: Bool,
        revealInProgressDifference: Bool = false
    ) -> ReconciliationVerdict {
        guard isReconciled else { return .notReconciled }
        return verdict(status: status, revealInProgressDifference: revealInProgressDifference)
    }
}
