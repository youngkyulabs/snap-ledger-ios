// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ReconciliationSummaryTests {
    let kst: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        cal.locale = Locale(identifier: "ko_KR")
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        return kst.date(from: comps)!
    }

    private func entry(_ y: Int, _ m: Int, _ d: Int, amount: Int) -> SavedEntry {
        SavedEntry(
            date: date(y, m, d),
            amount: amount,
            merchant: "가맹점",
            savedAt: date(y, m, d),
            csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv"
        )
    }

    @Test func displayVerdictShowsNotReconciledWhenNoSavedData() {
        // Show 'not reconciled' before actual values are saved or edited.
        let balances = [
            AccountMonthlyBalance(
                monthKey: 202_604,
                accountName: "통장",
                openingBalance: 1_000_000,
                closingBalance: 1_000_000
            ),
        ]
        let incomes = [IncomeItem(monthKey: 202_604, title: "월급", amount: 3_000_000)]
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(balances: balances, incomeItems: incomes),
            targetMonth: 202_604,
            calendar: kst
        )

        #expect(summary.difference != 0)
        #expect(summary.displayVerdict(status: .closed, isReconciled: false) == .notReconciled)
        // Display difference verdict when marked as reconciled.
        #expect(summary.displayVerdict(status: .closed, isReconciled: true).tone == .off)
    }

    @Test func computesActualRecordedAndDifference() {
        let reconciliation = MonthlyReconciliation(monthKey: 202_606)
        let balances = [
            AccountMonthlyBalance(
                monthKey: 202_606,
                accountName: "입출금",
                openingBalance: 1_000_000,
                closingBalance: 3_050_000,
                interestAmount: 0
            ),
            AccountMonthlyBalance(
                monthKey: 202_606,
                accountName: "적금",
                openingBalance: 2_000_000,
                closingBalance: 2_500_000,
                interestAmount: 10_000
            ),
        ]
        let entries = [
            entry(2026, 6, 1, amount: 250_000),
            entry(2026, 6, 2, amount: 200_000),
        ]

        let summary = ReconciliationSummary.compute(
            entries: entries,
            input: ReconciliationSummaryInput(
                reconciliation: reconciliation,
                balances: balances,
                savingsItems: [
                    SavingsItem(monthKey: 202_606, title: "저축", amount: 500_000),
                ],
                cardItems: [CardUsageItem(monthKey: 202_606, title: "카드", amount: 450_000)],
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 3_000_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        // Savings subtracted from actual spending, excluded from recorded spending.
        #expect(summary.actualSpending == 410_000)
        #expect(summary.recordedSpending == 450_000)
        #expect(summary.difference == -40_000)
    }

    @Test func cashAdjustmentWithdrawalsReduceActualSpendingBase() {
        let reconciliation = MonthlyReconciliation(monthKey: 202_606)
        let balances = [
            AccountMonthlyBalance(
                monthKey: 202_606,
                accountName: "입출금",
                openingBalance: 1_000_000,
                closingBalance: 3_900_000
            ),
        ]
        let adjustments = [
            CashAdjustment(
                monthKey: 202_606,
                title: "전월 카드대금",
                direction: .withdrawal,
                amount: 400_000
            ),
        ]

        let summary = ReconciliationSummary.compute(
            entries: [entry(2026, 6, 3, amount: 400_000)],
            input: ReconciliationSummaryInput(
                reconciliation: reconciliation,
                balances: balances,
                adjustments: adjustments,
                cardItems: [CardUsageItem(monthKey: 202_606, title: "카드", amount: 700_000)],
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 3_000_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.adjustmentNetAmount == -400_000)
        #expect(summary.actualSpending == 400_000)
        #expect(summary.recordedSpending == 400_000)
        #expect(summary.difference == 0)
    }

    @Test func cashAdjustmentDepositsIncreaseActualSpendingBase() {
        let reconciliation = MonthlyReconciliation(monthKey: 202_606)
        let balances = [
            AccountMonthlyBalance(
                monthKey: 202_606,
                accountName: "입출금",
                openingBalance: 500_000,
                closingBalance: 2_000_000
            ),
        ]
        let adjustments = [
            CashAdjustment(
                monthKey: 202_606,
                title: "환급",
                direction: .deposit,
                amount: 100_000
            ),
        ]

        let summary = ReconciliationSummary.compute(
            entries: [entry(2026, 6, 3, amount: 300_000)],
            input: ReconciliationSummaryInput(
                reconciliation: reconciliation,
                balances: balances,
                adjustments: adjustments,
                savingsItems: [
                    SavingsItem(monthKey: 202_606, title: "저축", amount: 100_000),
                ],
                cardItems: [CardUsageItem(monthKey: 202_606, title: "카드", amount: 300_000)],
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 2_000_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        // Savings deducted from actual spending.
        #expect(summary.adjustmentNetAmount == 100_000)
        #expect(summary.actualSpending == 800_000)
        #expect(summary.recordedSpending == 300_000)
        #expect(summary.difference == 500_000)
    }

    @Test func excludesOtherMonths() {
        let summary = ReconciliationSummary.compute(
            entries: [
                entry(2026, 5, 31, amount: 1_000),
                entry(2026, 6, 1, amount: 2_000),
            ],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                balances: [
                    AccountMonthlyBalance(monthKey: 202_605, accountName: "5월", openingBalance: 1, closingBalance: 2),
                    AccountMonthlyBalance(monthKey: 202_606, accountName: "6월", openingBalance: 10, closingBalance: 10),
                ],
                adjustments: [
                    CashAdjustment(
                        monthKey: 202_605,
                        title: "5월",
                        direction: .deposit,
                        amount: 999
                    ),
                    CashAdjustment(
                        monthKey: 202_606,
                        title: "6월",
                        direction: .deposit,
                        amount: 100
                    ),
                ],
                savingsItems: [
                    SavingsItem(monthKey: 202_606, title: "6월저축", amount: 3_000),
                    SavingsItem(monthKey: 202_605, title: "5월저축", amount: 999_999),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.recordedExpenseAmount == 2_000)
        // Recorded spending contains only expense entries; savings deducted from actual.
        #expect(summary.recordedSpending == 2_000)
        #expect(summary.openingBalanceTotal == 10)
        #expect(summary.adjustmentNetAmount == 100)
    }

    @Test func periodStatusTreatsCurrentAndFutureMonthsAsInProgress() {
        let today = date(2026, 6, 15)
        #expect(ReconciliationSummary.periodStatus(month: 202_605, today: today, calendar: kst) == .closed)
        #expect(ReconciliationSummary.periodStatus(month: 202_606, today: today, calendar: kst) == .inProgress)
        #expect(ReconciliationSummary.periodStatus(month: 202_607, today: today, calendar: kst) == .inProgress)
    }

    @Test func verdictForInProgressMonthIsNeutral() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 9_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        let verdict = summary.verdict(status: .inProgress)
        #expect(verdict.tone == .inProgress)
        #expect(verdict.headline == "진행 중")
    }

    @Test func verdictRevealsInProgressDifferenceOnDemand() {
        // Salary only -> difference 9,000 (actual > recorded).
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 9_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        // Default glance displays 'in progress'.
        #expect(summary.verdict(status: .inProgress).headline == "진행 중")
        // Reconciliation view reveals difference with in-progress tone.
        let revealed = summary.verdict(status: .inProgress, revealInProgressDifference: true)
        #expect(revealed.headline.contains("차이"))
        #expect(revealed.detail == "실제 쓴 돈이 더 커요")
        #expect(revealed.tone == .inProgress)
    }

    @Test func verdictKeepsInProgressWhenBalancedEvenIfRevealing() {
        // Balanced/empty in-progress month stays inProgress rather than balanced.
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(reconciliation: MonthlyReconciliation(monthKey: 202_606)),
            targetMonth: 202_606,
            calendar: kst
        )
        let revealed = summary.verdict(status: .inProgress, revealInProgressDifference: true)
        #expect(revealed.headline == "진행 중")
        #expect(revealed.tone == .inProgress)
    }

    @Test func verdictForClosedBalancedMonthIsNormal() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(reconciliation: MonthlyReconciliation(monthKey: 202_605)),
            targetMonth: 202_605,
            calendar: kst
        )
        let verdict = summary.verdict(status: .closed)
        #expect(verdict.tone == .balanced)
        #expect(verdict.headline == "정상")
        #expect(verdict.detail == "차이 없음")
    }

    @Test func verdictForClosedMonthDescribesDifferenceDirection() {
        // Actual (salary 1,000) > recorded (0)
        let actualHeavy = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_605),
                incomeItems: [IncomeItem(monthKey: 202_605, title: "월급", amount: 1_000)]
            ),
            targetMonth: 202_605,
            calendar: kst
        ).verdict(status: .closed)
        #expect(actualHeavy.tone == .off)
        #expect(actualHeavy.detail == "실제 쓴 돈이 더 커요")
        #expect(actualHeavy.headline.contains("차이"))

        // Recorded (1,000) > actual (0)
        let recordedHeavy = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_605),
                savingsItems: [SavingsItem(monthKey: 202_605, title: "저축", amount: 1_000)]
            ),
            targetMonth: 202_605,
            calendar: kst
        ).verdict(status: .closed)
        #expect(recordedHeavy.tone == .off)
        #expect(recordedHeavy.detail == "기록한 돈이 더 커요")
    }

    @Test func sumsCardItems() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                cardItems: [
                    CardUsageItem(monthKey: 202_606, title: "신한", amount: 300_000),
                    CardUsageItem(monthKey: 202_606, title: "현대", amount: 200_000),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.creditCardAmount == 500_000)
    }

    @Test func cardItemsContributeToActualSpending() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                cardItems: [
                    CardUsageItem(monthKey: 202_606, title: "신한", amount: 300_000),
                    CardUsageItem(monthKey: 202_606, title: "현대", amount: 200_000),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        // Card usage is included in actual spending.
        #expect(summary.actualSpending == 500_000)
    }

    @Test func sumsSavingsItems() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                savingsItems: [
                    SavingsItem(monthKey: 202_606, title: "적금", amount: 300_000),
                    SavingsItem(monthKey: 202_606, title: "펀드", amount: 200_000),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.savingsAmount == 500_000)
        // Savings deducted from actual spending.
        #expect(summary.recordedSpending == 0)
        #expect(summary.actualSpending == -500_000)
        #expect(summary.hasReconciliationData == true)
    }

    @Test func sumsIncomeItems() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606),
                incomeItems: [
                    IncomeItem(monthKey: 202_606, title: "월급", amount: 3_000_000),
                    IncomeItem(monthKey: 202_606, title: "보너스", amount: 500_000),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        // Income is included in actual spending.
        #expect(summary.salaryAmount == 3_500_000)
        #expect(summary.actualSpending == 3_500_000)
        #expect(summary.hasReconciliationData == true)
    }
}

// MARK: - hasStartedReconciliation / isReconciled(status:)

@MainActor
struct ReconciliationSummaryStartedTests {
    let kst: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        cal.locale = Locale(identifier: "ko_KR")
        return cal
    }()

    @Test func hasStartedReconciliationFalseWhenPrefill() {
        // Prefilled state: closing equals opening, card usage 0 -> not started.
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: 202_606, accountName: "통장",
                        openingBalance: 1_000_000, closingBalance: 1_000_000
                    ),
                ],
                cardItems: [CardUsageItem(monthKey: 202_606, title: "신한", amount: 0)],
                incomeItems: [IncomeItem(monthKey: 202_606, title: "월급", amount: 3_000_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        #expect(summary.hasStartedReconciliation == false)
    }

    @Test func hasStartedReconciliationTrueWhenClosingDiffers() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: 202_606, accountName: "통장",
                        openingBalance: 1_000_000, closingBalance: 900_000
                    ),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        #expect(summary.hasStartedReconciliation == true)
    }

    @Test func hasStartedReconciliationTrueWhenCardEntered() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                cardItems: [CardUsageItem(monthKey: 202_606, title: "신한", amount: 50_000)]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        #expect(summary.hasStartedReconciliation == true)
    }

    @Test func isReconciledClosedMonthUsesSavedData() {
        // Closed month with saved data -> considered reconciled.
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: 202_605, accountName: "통장",
                        openingBalance: 1_000_000, closingBalance: 1_000_000
                    ),
                ]
            ),
            targetMonth: 202_605,
            calendar: kst
        )
        #expect(summary.hasStartedReconciliation == false)
        #expect(summary.hasReconciliationData == true)
        #expect(summary.isReconciled(status: .closed) == true)
    }

    @Test func isReconciledClosedMonthFalseWhenNoData() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(),
            targetMonth: 202_605,
            calendar: kst
        )
        #expect(summary.isReconciled(status: .closed) == false)
    }

    @Test func isReconciledInProgressUsesStartedFlag() {
        let prefill = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: 202_606, accountName: "통장",
                        openingBalance: 500_000, closingBalance: 500_000
                    ),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        #expect(prefill.isReconciled(status: .inProgress) == false)

        let started = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: 202_606, accountName: "통장",
                        openingBalance: 500_000, closingBalance: 400_000
                    ),
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )
        #expect(started.isReconciled(status: .inProgress) == true)
    }
}
