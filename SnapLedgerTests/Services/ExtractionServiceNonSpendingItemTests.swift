import Foundation
import Testing
@testable import SnapLedger

/// Verifies that bookkeeping lines of a notification (incentive, balance, points) do not become entries.
@MainActor
struct ExtractionServiceNonSpendingItemTests {
    private func txn(_ amount: Int, _ merchant: String, items: [PaymentLineItem] = []) -> PaymentTransaction {
        PaymentTransaction(date: "2026-10-25", amount: amount, merchant: merchant, category: "", items: items)
    }

    private func item(_ name: String, _ amount: Int) -> PaymentLineItem {
        PaymentLineItem(name: name, amount: amount)
    }

    private func drop(_ trans: PaymentTransaction) -> PaymentTransaction {
        FoundationModelsExtractionService.droppingNonSpendingItems(trans)
    }

    // MARK: - droppingNonSpendingItems

    /// A local-currency notification: the payment stands on its own and the incentive line came back as an item.
    @Test func dropsIncentiveLineBesideThePayment() {
        let out = drop(txn(6600, "행복마트 역앞점", items: [item("지역사랑카드 추가형인센티브", 489)]))
        #expect(out == txn(6600, "행복마트 역앞점"))
    }

    @Test func dropsBalanceAndRunningTotalLines() {
        let out = drop(txn(6600, "행복마트", items: [item("총 보유 잔액", 78450), item("누적", 1_240_500)]))
        #expect(out == txn(6600, "행복마트"))
    }

    /// The remaining items add up to the payment, so the points line is not part of it.
    @Test func dropsPointsLineWhenTheOtherItemsMakeTheTotal() {
        let out = drop(txn(13000, "양말가게", items: [item("양말", 8000), item("장갑", 5000), item("포인트 적립", 130)]))
        #expect(out == txn(13000, "양말가게", items: [item("양말", 8000), item("장갑", 5000)]))
    }

    /// A product whose name holds a label word is part of the receipt's total.
    @Test func keepsLabelNamedProductThatIsPartOfTheTotal() {
        let receipt = txn(42000, "옷가게", items: [item("포인트 니트", 29000), item("양말", 13000)])
        #expect(drop(receipt) == receipt)
    }

    @Test func keepsLoneLabelNamedProductAtTheTotal() {
        let receipt = txn(29000, "옷가게", items: [item("포인트 니트", 29000)])
        #expect(drop(receipt) == receipt)
    }

    /// Without the label item the rest does not make the total either, so nothing tells it apart from a product.
    @Test func keepsLabelItemWhenTheRestDoesNotMakeTheTotal() {
        let receipt = txn(50000, "옷가게", items: [item("포인트 니트", 29000), item("양말", 13000)])
        #expect(drop(receipt) == receipt)
    }

    @Test func keepsLabelItemWhenThePaymentAmountIsUnknown() {
        let unknown = txn(0, "행복마트", items: [item("추가형인센티브", 489)])
        #expect(drop(unknown) == unknown)
    }

    @Test func keepsOrdinaryItems() {
        let receipt = txn(9000, "카페", items: [item("아메리카노", 4000), item("라떼", 5000)])
        #expect(drop(receipt) == receipt)
    }

    // MARK: - normalize

    /// Runs before folding: with an issuer-like merchant, folding would move the incentive into the amount.
    @Test func normalizeKeepsThePaymentWhenTheMerchantRepeatsInTheIncentiveLine() {
        let extraction = PaymentExtraction(transactions: [
            txn(6600, "지역사랑카드", items: [item("지역사랑카드 추가형인센티브", 489)])
        ])
        let out = FoundationModelsExtractionService.normalize(extraction)
        #expect(out.transactions.count == 1)
        #expect(out.transactions.first?.amount == 6600)
        #expect(out.transactions.first?.items.isEmpty == true)
    }

    // MARK: - amount candidates

    @Test func amountsExcludeIncentiveLine() {
        let text = "결제 완료 6,600원\n행복마트 역앞점\n지역사랑카드 추가형인센티브 489원"
        #expect(CandidateHeuristics.amounts(from: text) == [6600])
    }
}
