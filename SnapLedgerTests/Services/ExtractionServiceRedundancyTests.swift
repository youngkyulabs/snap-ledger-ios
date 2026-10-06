import Foundation
import Testing
@testable import SnapLedger

/// Verifies folding of lone items that restate the payment and dropping of duplicate rows.
@MainActor
struct ExtractionServiceRedundancyTests {
    private func txn(
        _ amount: Int,
        _ merchant: String,
        items: [PaymentLineItem] = [],
        date: String = "2026-09-30"
    ) -> PaymentTransaction {
        PaymentTransaction(date: date, amount: amount, merchant: merchant, category: "", items: items)
    }

    private func item(_ name: String, _ amount: Int) -> PaymentLineItem {
        PaymentLineItem(name: name, amount: amount)
    }

    // MARK: - foldingRestatedItem

    @Test func foldsItemThatRepeatsMerchant() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(2500, "메가커피", items: [item("메가커피 선릉", 2500)])
        )
        #expect(out == txn(2500, "메가커피"))
    }

    /// The entry saved the item's amount before folding, so folding keeps it.
    @Test func foldUsesItemAmountWhenTotalDisagrees() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(14900, "메가커피 선릉", items: [item("메가커피 선릉", 2500)])
        )
        #expect(out == txn(2500, "메가커피 선릉"))
    }

    @Test func foldIgnoresSpacingAndCase() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(13500, "Netflix", items: [item("NETFLIX .COM", 13500)])
        )
        #expect(out.items.isEmpty)
        #expect(out.merchant == "Netflix")
    }

    @Test func foldNamesMerchantlessTransactionAfterItem() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(13500, "", items: [item("NETFLIX.COM", 13500)])
        )
        #expect(out == txn(13500, "NETFLIX.COM"))
    }

    @Test func foldTreatsCardIssuerAsMissingMerchant() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(13500, "신한카드", items: [item("NETFLIX.COM", 13500)])
        )
        #expect(out == txn(13500, "NETFLIX.COM"))
    }

    @Test func foldMatchesNamesDifferingOnlyInSpacing() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(2500, "메가커피 선릉", items: [item("메가커피선릉", 2500)])
        )
        #expect(out == txn(2500, "메가커피 선릉"))
    }

    /// A shared leading run of letters is not the same name.
    @Test func foldKeepsItemThatOnlySharesLeadingLetters() {
        let input = txn(1500, "CU", items: [item("CUP누들", 1500)])
        #expect(FoundationModelsExtractionService.foldingRestatedItem(input) == input)
    }

    @Test func foldKeepsItemOfMerchantlessTransactionWhenAmountsDiffer() {
        let input = txn(20000, "", items: [item("선크림", 25000)])
        #expect(FoundationModelsExtractionService.foldingRestatedItem(input) == input)
    }

    /// A distinct item name may be the real merchant, as when the model takes a card product name as the merchant.
    @Test func foldKeepsItemWithDistinctName() {
        let input = txn(16000, "삼성법인", items: [item("찌개애감동", 16000)])
        #expect(FoundationModelsExtractionService.foldingRestatedItem(input) == input)
    }

    @Test func foldKeepsSingleItemReceipt() {
        let input = txn(3200, "이디야커피 역삼점", items: [item("아메리카노(L)", 3200)])
        #expect(FoundationModelsExtractionService.foldingRestatedItem(input) == input)
    }

    @Test func foldLeavesMultiItemBreakdown() {
        let input = txn(11200, "투썸플레이스", items: [item("투썸플레이스 케이크", 6700), item("아메리카노", 4500)])
        #expect(FoundationModelsExtractionService.foldingRestatedItem(input) == input)
    }

    @Test func foldDropsNamelessItem() {
        let out = FoundationModelsExtractionService.foldingRestatedItem(
            txn(4100, "GS25 역삼점", items: [item(" ", 4100)])
        )
        #expect(out == txn(4100, "GS25 역삼점"))
    }

    /// An adopted item name still goes through the payment provider mapping.
    @Test func normalizeMapsAdoptedItemName() {
        let input = PaymentExtraction(transactions: [txn(23000, "", items: [item("KAKAO PAY", 23000)])])
        let out = FoundationModelsExtractionService.normalize(input, ocrText: "카카오페이 23,000원 09/30")
        #expect(out.transactions.first?.merchant == "카카오페이")
        #expect(out.transactions.first?.items.isEmpty == true)
    }

    // MARK: - droppingRedundantTransactions

    @Test func dropsMerchantlessRowRepeatingReceiptTotal() {
        let receipt = txn(612_300, "홈플러스 강남점", items: [item("삼겹살 600g", 14900), item("계란 한판", 6500)])
        let out = FoundationModelsExtractionService.droppingRedundantTransactions([receipt, txn(612_300, "")])
        #expect(out == [receipt])
    }

    @Test func dropsEmptyRowBesideRealTransaction() {
        let receipt = txn(612_300, "홈플러스 강남점")
        let out = FoundationModelsExtractionService.droppingRedundantTransactions([receipt, txn(0, "", date: "")])
        #expect(out == [receipt])
    }

    /// The approval line names the card issuer, which normalization clears before the duplicate check.
    @Test func normalizeDropsCardIssuerTwinOfReceiptTotal() {
        let input = PaymentExtraction(transactions: [txn(612_300, "홈플러스 강남점"), txn(612_300, "신한카드")])
        let out = FoundationModelsExtractionService.normalize(input, ocrText: "합계 612,300원\n신한카드 일시불 612,300원")
        #expect(out.transactions.map(\.merchant) == ["홈플러스 강남점"])
    }

    /// The same amount on another day is a separate payment even without a merchant.
    @Test func keepsMerchantlessRowOnDifferentDate() {
        let input = [txn(4500, "메가커피 역삼", date: "2026-09-29"), txn(4500, "", date: "2026-09-30")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsMerchantlessTwinWhoseDateIsMissing() {
        let input = [txn(612_300, "홈플러스 강남점", date: "2026-06-14"), txn(612_300, "", date: "")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    /// Items become their own entries, so a row that carries them is never dropped.
    @Test func keepsMerchantlessZeroRowWithItems() {
        let input = [txn(612_300, "홈플러스 강남점"), txn(0, "", items: [item("삼겹살 600g", 14900)])]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsMerchantlessTwinWithItems() {
        let input = [txn(11200, "투썸플레이스"), txn(11200, "", items: [item("아이스 아메리카노", 4500), item("티라미수", 6700)])]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsSameAmountPaymentsAtDifferentMerchants() {
        let input = [txn(4500, "메가커피 역삼"), txn(4500, "컴포즈커피 선릉")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsLoneMerchantlessTransaction() {
        let input = [txn(13500, "")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsMerchantlessRowsWithoutNamedTwin() {
        let input = [txn(4500, ""), txn(4500, "")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsMerchantlessRowWithDifferentAmount() {
        let input = [txn(612_300, "홈플러스 강남점"), txn(55663, "")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    @Test func keepsEmptyRowsWhenNothingElseCarriesData() {
        let input = [txn(0, ""), txn(0, "")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }
}
