import Foundation
import Testing
@testable import SnapLedger

/// Verifies placeholder guards preventing prompt example leakage.
@MainActor
struct ExtractionServiceLeakGuardTests {
    private let defaultCategories = AppSettings.defaultPresets

    // MARK: - Prompt Placeholders

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
        // Verify Apple is not used as an example merchant.
        #expect(!prompt.contains("merchant=\"Apple\""))
    }

    /// Verifies anti-split guidance and example in prompt.
    @Test func instructionsIncludeSingleChargeMergeGuidance() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("1개로 합치세요"))
        #expect(prompt.contains("예시상호4"))
        // Anti-merge rule: keep separate transactions if merchant or time differs.
        #expect(prompt.contains("별개 거래"))
    }

    // MARK: - Normalize Dropping

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
        // Only prefix match triggers placeholder drop.
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
