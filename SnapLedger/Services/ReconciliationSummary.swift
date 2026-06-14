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
    /// 사용자가 실제 정산값을 입력했는지(월초≠월말 또는 카드 금액 입력). 프리필/빈 상태는 false.
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
        // 수입·카드는 항목별 합계.
        let salary = monthIncomes.reduce(0) { $0 + $1.amount }
        let card = monthCards.reduce(0) { $0 + $1.amount }
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
        // 저축은 "실제 쓴 돈"(실제 소비)에서 제외한다. 저축으로 빠진 돈은 소비가 아니므로 잔액 변화에서
        // 차감하고, "기록한 돈"에는 지출 기록만 남긴다. 저축을 actual에서 빼든 recorded에 더하든
        // difference(정산 차이·판정)는 동일하게 유지된다 — 표시 숫자만 바뀐다.
        let actual = opening + salary + interest + adjustmentNet + card - closing - savings
        let recorded = recordedExpense
        let hasData = monthReconciliation != nil || !monthBalances.isEmpty
            || !monthAdjustments.isEmpty || !monthSavings.isEmpty || !monthCards.isEmpty
            || !monthIncomes.isEmpty
        let started = monthBalances.contains { $0.openingBalance != $0.closingBalance }
            || monthCards.contains { $0.amount != 0 }

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
            hasReconciliationData: hasData,
            hasStartedReconciliation: started
        )
    }
}

/// 정산 대상 달이 아직 진행 중(현재·미래 달)인지, 이미 마감된 과거 달인지.
/// 진행 중인 달은 아직 마감 전이라 정산 차이가 의미 없으므로 '진행 중'으로만 표시한다.
enum ReconciliationPeriodStatus: Equatable {
    case inProgress
    case closed
}

/// 정산 결과를 사용자에게 보여줄 한 줄 판정 (제목 + 보조 설명 + 색상 톤).
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

    /// 화면에 정산 결과를 '확정값'으로 보여줄지 여부.
    /// - 마감된 달: 저장된 정산 데이터가 있으면 확정(잔액 변화가 없어 '정상'이어도 표시).
    /// - 진행 중인 달: 사용자가 실제 값을 입력했을 때만 확정(프리필 노이즈 차단).
    func isReconciled(status: ReconciliationPeriodStatus) -> Bool {
        switch status {
        case .closed:     return hasReconciliationData
        case .inProgress: return hasStartedReconciliation
        }
    }

    /// `revealInProgressDifference`가 true면 진행 중인 달이라도 차이가 있을 때 그 차이를 보여준다
    /// (정산 화면 전용 — 입력하면서 차이를 바로 확인). 톤은 '진행 중'(중립)으로 두어 확정 전임을 알린다.
    /// 차이가 0이면 빈 달이 '정상'으로 오표기되지 않도록 '진행 중'으로 표시한다.
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
    /// 아직 저장된 정산 데이터가 없는 달(전월 값으로 프리필만 됐거나 빈 달)에 보여줄 중립 판정.
    static let notReconciled = ReconciliationVerdict(tone: .inProgress, headline: "아직 정산 전", detail: "")
}

extension ReconciliationSummary {
    /// 화면 표시용 판정. 저장된 정산 데이터가 없으면(`isReconciled == false`) 차이 대신
    /// '아직 정산 전'을 보여준다 — 전월 값으로 프리필만 된 정산 화면과 빈 DB를 읽는 예산 탭이
    /// 같은 달에 대해 같은 결론을 내도록 맞춘다.
    func displayVerdict(
        status: ReconciliationPeriodStatus,
        isReconciled: Bool,
        revealInProgressDifference: Bool = false
    ) -> ReconciliationVerdict {
        guard isReconciled else { return .notReconciled }
        return verdict(status: status, revealInProgressDifference: revealInProgressDifference)
    }
}
