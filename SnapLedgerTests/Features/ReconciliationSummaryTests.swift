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

    @Test func computesActualRecordedAndDifference() {
        let reconciliation = MonthlyReconciliation(
            monthKey: 202_606,
            salaryAmount: 3_000_000,
            creditCardAmount: 450_000
        )
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
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.actualSpending == 910_000)
        #expect(summary.recordedSpending == 950_000)
        #expect(summary.difference == -40_000)
    }

    @Test func cashAdjustmentWithdrawalsReduceActualSpendingBase() {
        let reconciliation = MonthlyReconciliation(
            monthKey: 202_606,
            salaryAmount: 3_000_000,
            creditCardAmount: 700_000
        )
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
                date: date(2026, 6, 25),
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
                adjustments: adjustments
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
        let reconciliation = MonthlyReconciliation(
            monthKey: 202_606,
            salaryAmount: 2_000_000,
            creditCardAmount: 300_000
        )
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
                date: date(2026, 6, 10),
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
                ]
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.adjustmentNetAmount == 100_000)
        #expect(summary.actualSpending == 900_000)
        #expect(summary.recordedSpending == 400_000)
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
                        date: date(2026, 5, 1),
                        title: "5월",
                        direction: .deposit,
                        amount: 999
                    ),
                    CashAdjustment(
                        monthKey: 202_606,
                        date: date(2026, 6, 1),
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
        #expect(summary.recordedSpending == 5_000)
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
            input: ReconciliationSummaryInput(reconciliation: MonthlyReconciliation(monthKey: 202_606, salaryAmount: 9_000)),
            targetMonth: 202_606,
            calendar: kst
        )
        let verdict = summary.verdict(status: .inProgress)
        #expect(verdict.tone == .inProgress)
        #expect(verdict.headline == "진행 중")
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
        // 실제(월급 1,000) > 기록(0)
        let actualHeavy = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(reconciliation: MonthlyReconciliation(monthKey: 202_605, salaryAmount: 1_000)),
            targetMonth: 202_605,
            calendar: kst
        ).verdict(status: .closed)
        #expect(actualHeavy.tone == .off)
        #expect(actualHeavy.detail == "실제 쓴 돈이 더 커요")
        #expect(actualHeavy.headline.contains("차이"))

        // 기록(저축 1,000) > 실제(0)
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

        // 카드 사용액은 actualSpending 계산식의 항 — 잔액·월급·자금변동이 모두 0이면 카드 합계와 같다.
        // (예산탭이 cardItems를 안 넘겨 카드 금액을 0으로 계산하던 회귀를 막는다.)
        #expect(summary.actualSpending == 500_000)
    }

    @Test func usesLegacyCreditCardAmountWhenNoCardItems() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606, creditCardAmount: 450_000)
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.creditCardAmount == 450_000)
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
        #expect(summary.recordedSpending == 500_000)
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

        // 수입은 actualSpending 계산식의 항 — 잔액·카드·자금변동이 0이면 수입 합계와 같다.
        #expect(summary.salaryAmount == 3_500_000)
        #expect(summary.actualSpending == 3_500_000)
        #expect(summary.hasReconciliationData == true)
    }

    @Test func usesLegacySalaryAmountWhenNoIncomeItems() {
        let summary = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                reconciliation: MonthlyReconciliation(monthKey: 202_606, salaryAmount: 2_000_000)
            ),
            targetMonth: 202_606,
            calendar: kst
        )

        #expect(summary.salaryAmount == 2_000_000)
    }
}
