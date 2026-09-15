import Foundation
import Testing
@testable import SnapLedger

/// Verifies that a card's previous-month bill is treated as an outflow of the current month.
@MainActor
struct PreviousCardUsageTests {
    private func summary(
        opening: Int,
        closing: Int,
        cards: [(amount: Int, previous: Int)],
        month: Int = 202_608
    ) -> ReconciliationSummary {
        ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: month,
                        accountName: "주거래",
                        openingBalance: opening,
                        closingBalance: closing
                    ),
                ],
                cardItems: cards.enumerated().map { index, card in
                    CardUsageItem(
                        monthKey: month,
                        title: "카드\(index)",
                        amount: card.amount,
                        previousAmount: card.previous,
                        sortOrder: index
                    )
                }
            ),
            targetMonth: month
        )
    }

    @Test func previousCardBillOffsetsBalanceDrop() {
        // The prior month's bill left the account this month, so it is not this month's spending.
        let result = summary(
            opening: 1_000_000,
            closing: 500_000,
            cards: [(amount: 300_000, previous: 200_000)]
        )
        #expect(result.previousCardAmount == 200_000)
        #expect(result.actualSpending == 600_000)
    }

    @Test func previousCardMatchesEquivalentWithdrawalAdjustment() {
        // Recording the bill on the card item must equal the old 자금변동 출금 workaround.
        let month = 202_608
        let viaCard = summary(
            opening: 1_000_000, closing: 500_000,
            cards: [(amount: 300_000, previous: 200_000)], month: month
        )
        let viaAdjustment = ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: month,
                        accountName: "주거래",
                        openingBalance: 1_000_000,
                        closingBalance: 500_000
                    ),
                ],
                adjustments: [
                    CashAdjustment(
                        monthKey: month,
                        title: "전월 카드대금",
                        direction: .withdrawal,
                        amount: 200_000
                    ),
                ],
                cardItems: [
                    CardUsageItem(monthKey: month, title: "카드0", amount: 300_000),
                ]
            ),
            targetMonth: month
        )
        #expect(viaCard.actualSpending == viaAdjustment.actualSpending)
    }

    @Test func previousCardAloneStartsReconciliation() {
        // Entering only the prior bill still counts as real figures, not carry-forward noise.
        let result = summary(
            opening: 1_000_000,
            closing: 1_000_000,
            cards: [(amount: 0, previous: 200_000)]
        )
        #expect(result.hasStartedReconciliation)
    }

    @Test func zeroPreviousCardLeavesSpendingUnchanged() {
        let result = summary(
            opening: 1_000_000,
            closing: 500_000,
            cards: [(amount: 300_000, previous: 0)]
        )
        #expect(result.previousCardAmount == 0)
        #expect(result.actualSpending == 800_000)
    }

    @Test func csvRoundTripsPreviousCardAmount() {
        // Export splits the card into two rows; import must merge them back onto one item.
        let content = """
        종류,항목,계좌,방향,금액,메모
        카드사용액,신한카드,,,300000,
        전월카드대금,신한카드,,,200000,
        """
        #expect(ReconciliationCSVParser.parse(content).skipped == 0)
        let draft = SampleDataParsing.parseReconciliationDraft(content)
        #expect(draft.cards.count == 1)
        #expect(draft.cards.first?.title == "신한카드")
        #expect(draft.cards.first?.amount == 300_000)
        #expect(draft.cards.first?.previousAmount == 200_000)
    }
}
