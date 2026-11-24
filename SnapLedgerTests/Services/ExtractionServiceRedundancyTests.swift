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
    /// Mirrors a measured answer: the dated receipt, then an undated twin named after the card issuer.
    @Test func normalizeDropsCardIssuerTwinOfReceiptTotal() {
        let receipt = txn(612_300, "홈플러스 강남점", items: [item("삼겹살", 1000), item("계란 한판", 4740)], date: "2026-06-14")
        let input = PaymentExtraction(transactions: [receipt, txn(612_300, "신한카드", date: "")])
        let out = FoundationModelsExtractionService.normalize(
            input, ocrText: "홈플러스 강남점\n2026-06-14 18:32\n합계 612,300원\n신한카드 일시불 612,300원"
        )
        #expect(out.transactions.map(\.merchant) == ["홈플러스 강남점"])
    }

    /// The same amount on another day is a separate payment even without a merchant.
    @Test func keepsMerchantlessRowOnDifferentDate() {
        let input = [txn(4500, "메가커피 역삼", date: "2026-09-29"), txn(4500, "", date: "2026-09-30")]
        #expect(FoundationModelsExtractionService.droppingRedundantTransactions(input) == input)
    }

    /// A row with no merchant, items, or date carries nothing beyond the amount it repeats.
    @Test func dropsUndatedTwinOfDatedTransaction() {
        let receipt = txn(612_300, "홈플러스 강남점", date: "2026-06-14")
        let out = FoundationModelsExtractionService.droppingRedundantTransactions([receipt, txn(612_300, "", date: "")])
        #expect(out == [receipt])
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

/// Verifies folding of lone items the model made up: status labels and names the source text does not hold.
@MainActor
struct ExtractionServiceMadeUpItemTests {
    private func txn(_ amount: Int, _ merchant: String, items: [PaymentLineItem] = []) -> PaymentTransaction {
        PaymentTransaction(date: "2026-10-25", amount: amount, merchant: merchant, category: "", items: items)
    }

    private func item(_ name: String, _ amount: Int) -> PaymentLineItem {
        PaymentLineItem(name: name, amount: amount)
    }

    private func fold(_ trans: PaymentTransaction, source: String? = nil) -> PaymentTransaction {
        FoundationModelsExtractionService.foldingRestatedItem(trans, sourceText: source)
    }

    @Test func foldsStatusLabelItem() {
        let source = "결제 완료 6,600원\n행복마트 역앞점"
        let out = fold(txn(6600, "행복마트 역앞점", items: [item("결제 완료", 6600)]), source: source)
        #expect(out == txn(6600, "행복마트 역앞점"))
    }

    @Test func foldsStatusLabelItemWithoutSourceText() {
        #expect(fold(txn(3200, "편의점", items: [item("일시불", 3200)])) == txn(3200, "편의점"))
    }

    @Test func foldsItemNamedWithWordsTheSourceDoesNotHold() {
        let source = "[체크카드] 승인 8,700원 일시불 10/09 14:22 별다방 역삼점"
        let out = fold(txn(8700, "별다방 역삼점", items: [item("카페 음료", 8700)]), source: source)
        #expect(out == txn(8700, "별다방 역삼점"))
    }

    /// The model sometimes takes a card product name as the merchant and puts the real merchant in the item.
    @Test func keepsItemPrintedInTheSource() {
        let source = "법인 체크 승인 9,000원 일시불 10/10 12:41 찌개마을"
        let trans = txn(9000, "법인 체크", items: [item("찌개마을", 9000)])
        #expect(fold(trans, source: source) == trans)
    }

    /// OCR breaks and spaces a name differently, so each word is looked up on its own.
    @Test func keepsItemWhoseWordsAreAllInTheSource() {
        let source = "결제 완료\n기모맨투맨 그레이 L\n1개 34,000원"
        let trans = txn(34000, "간편결제 머니", items: [item("기모 맨투맨 1개", 34000)])
        #expect(fold(trans, source: source) == trans)
    }

    @Test func keepsMadeUpItemWhenItsAmountDiffers() {
        let source = "별다방 역삼점 8,700원"
        let trans = txn(8700, "별다방 역삼점", items: [item("카페 음료", 4500)])
        #expect(fold(trans, source: source) == trans)
    }

    @Test func keepsDistinctItemWhenTheSourceIsUnknown() {
        let trans = txn(8700, "별다방 역삼점", items: [item("카페 음료", 8700)])
        #expect(fold(trans) == trans)
    }

    /// A status label is not a merchant, so it is dropped instead of being moved up.
    @Test func doesNotPromoteStatusLabelToMerchant() {
        #expect(fold(txn(3200, "", items: [item("결제 완료", 3200)])) == txn(3200, ""))
    }

    @Test func normalizeFoldsMadeUpItemUsingTheSourceText() {
        let extraction = PaymentExtraction(transactions: [txn(8700, "별다방 역삼점", items: [item("카페 음료", 8700)])])
        let out = FoundationModelsExtractionService.normalize(
            extraction, ocrText: "승인 8,700원 일시불 2026-10-25 14:22 별다방 역삼점"
        )
        #expect(out.transactions.first?.items.isEmpty == true)
        #expect(out.transactions.first?.amount == 8700)
    }
}
