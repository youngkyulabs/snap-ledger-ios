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
        let monthCards = input.cardItems.filter { $0.monthKey == targetMonth }
        let monthIncomes = input.incomeItems.filter { $0.monthKey == targetMonth }
        let monthReconciliation = input.reconciliation?.monthKey == targetMonth ? input.reconciliation : nil

        let opening = monthBalances.reduce(0) { $0 + $1.openingBalance }
        let closing = monthBalances.reduce(0) { $0 + $1.closingBalance }
        let interest = monthBalances.reduce(0) { $0 + $1.interestAmount }
        // 수입은 항목별 합계. 항목이 없는 레거시 데이터는 단일 salaryAmount로 폴백.
        let salary = monthIncomes.isEmpty
            ? (monthReconciliation?.salaryAmount ?? 0)
            : monthIncomes.reduce(0) { $0 + $1.amount }
        // 카드는 항목별 합계. 항목이 없는 레거시 데이터는 단일 creditCardAmount로 폴백.
        let card = monthCards.isEmpty
            ? (monthReconciliation?.creditCardAmount ?? 0)
            : monthCards.reduce(0) { $0 + $1.amount }
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
            || !monthAdjustments.isEmpty || !monthSavings.isEmpty || !monthCards.isEmpty
            || !monthIncomes.isEmpty

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

/// 정산 대상 달이 아직 진행 중(현재·미래 달)인지, 이미 마감된 과거 달인지.
/// 진행 중인 달은 기말 잔액이 아직 안 채워져 대사 차이가 의미 없으므로 문구를 다르게 한다.
enum ReconciliationPeriodStatus: Equatable {
    case inProgress
    case closed
}

/// 대사 결과를 사용자에게 보여줄 한 줄 판정 (제목 + 보조 설명 + 색상 톤).
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

    func verdict(status: ReconciliationPeriodStatus) -> ReconciliationVerdict {
        switch status {
        case .inProgress:
            return ReconciliationVerdict(
                tone: .inProgress,
                headline: "진행 중",
                detail: "기말 잔액을 채우면 대사돼요"
            )
        case .closed:
            if isBalanced {
                return ReconciliationVerdict(tone: .balanced, headline: "정상", detail: "차이 없음")
            }
            return ReconciliationVerdict(
                tone: .off,
                headline: "\(abs(difference).formatted(.number))원 차이",
                detail: difference > 0 ? "실제 쓴 돈이 더 커요" : "기록한 돈이 더 커요"
            )
        }
    }
}
