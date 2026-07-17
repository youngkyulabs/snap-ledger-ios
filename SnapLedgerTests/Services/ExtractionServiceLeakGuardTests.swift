import Foundation
import Testing
@testable import SnapLedger

/// FoundationModels가 instructions의 예시 블록 데이터를 그대로 베껴 응답하던
/// 환각을 막기 위한 두 가지 방어선:
///   1) prompt 자체에 명백한 placeholder('예시상호N', '예시품목N')만 노출
///   2) normalize에서 placeholder로 시작하는 merchant/items.name이 보이면 transaction을 통째로 drop
@MainActor
struct ExtractionServiceLeakGuardTests {
    private let defaultCategories = AppSettings.defaultPresets

    // MARK: - prompt 측 방어선

    @Test func instructionsUsePlaceholderTokensNotRealBrands() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("예시상호1"))
        #expect(prompt.contains("예시상호2"))
        #expect(prompt.contains("예시품목1"))
        #expect(!prompt.contains("스타벅스"))
        #expect(!prompt.contains("아메리카노"))
        #expect(!prompt.contains("카페라떼"))
        #expect(!prompt.contains("쿠팡"))
        // "Apple"은 짧고 일반적이라 정확 매치만 — 예시 머천트로는 안 쓴다는 확인.
        #expect(!prompt.contains("merchant=\"Apple\""))
    }

    /// 한 결제가 여러 줄/중복 금액으로 보여도 1건으로 합치라는 anti-split 가이드와
    /// 반례(예시상호4)가 프롬프트에 유지되는지 — 리팩터로 조용히 사라지는 것 방지.
    @Test func instructionsIncludeSingleChargeMergeGuidance() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("1개로 합치세요"))
        #expect(prompt.contains("예시상호4"))
        // 과병합 방지: 가맹점·시각이 다르면 같은 금액이어도 별개 거래로 유지.
        #expect(prompt.contains("별개 거래"))
    }

    // MARK: - normalize 측 방어선

    @Test func normalizeDropsTransactionWithExampleMerchantToken() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1111, merchant: "예시상호1",
                category: "4. 생활・쇼핑", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.isEmpty)
    }

    @Test func normalizeDropsAllExampleMerchantVariants() {
        for suffix in ["1", "2", "3", "A", "B"] {
            let merchant = "예시상호" + suffix
            let input = PaymentExtraction(transactions: [
                PaymentTransaction(
                    date: "2026-05-17", amount: 1000, merchant: merchant,
                    category: "", items: []
                ),
            ])
            let out = FoundationModelsExtractionService.normalize(input)
            #expect(out.transactions.isEmpty, "\(merchant) should be dropped")
        }
    }

    @Test func normalizeDropsTransactionWithExampleItemToken() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 7777, merchant: "어떤가게",
                category: "3. 식비",
                items: [
                    PaymentLineItem(name: "예시품목1", amount: 3333),
                    PaymentLineItem(name: "예시품목2", amount: 4444),
                ]
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.isEmpty)
    }

    @Test func normalizeKeepsValidTransactionsAlongsideLeakedOnes() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1111, merchant: "예시상호1",
                category: "", items: []
            ),
            PaymentTransaction(
                date: "2026-05-17", amount: 15000, merchant: "다이소",
                category: "4. 생활・쇼핑", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.count == 1)
        #expect(out.transactions[0].merchant == "다이소")
    }

    @Test func normalizeDoesNotDropMerchantsThatMerelyContainExampleSubstring() {
        // prefix 일치만 잡고, 본문 어딘가에 "예시상호"가 들어가는 합법 머천트는 통과.
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000, merchant: "한국예시상호연구소",
                category: "", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.count == 1)
        #expect(out.transactions[0].merchant == "한국예시상호연구소")
    }
}
