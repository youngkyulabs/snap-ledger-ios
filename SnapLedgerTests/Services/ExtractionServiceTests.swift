// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ExtractionServiceTests {
    @Test func stubReturnsConfiguredResult() async throws {
        let expected = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17",
                amount: 5000,
                merchant: "스타벅스",
                category: "카페",
                items: []
            ),
        ])
        let stub = StubExtractionService(result: expected)
        let got = try await stub.extract(from: "any input")
        #expect(got == expected)
    }

    private let defaultCategories = AppSettings.defaultPresets

    @Test func instructionsIncludeTodaysYear() {
        let date = DateComponents(
            calendar: .init(identifier: .gregorian),
            year: 2026, month: 5, day: 17
        ).date!
        let prompt = FoundationModelsExtractionService.instructions(
            today: date, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("2026-05-17"))
    }

    @Test func emptyCustomGuideDoesNotAppendSection() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(!prompt.contains("사용자 가이드"))
    }

    @Test func whitespaceOnlyCustomGuideIsTreatedAsEmpty() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "   \n\t  ", categories: defaultCategories
        )
        #expect(!prompt.contains("사용자 가이드"))
    }

    @Test func nonEmptyCustomGuideAppearsInPrompt() {
        let guide = "내 카드는 항상 '비씨카드'로 시작해. '비씨카드' 단어는 무시해."
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: guide, categories: defaultCategories
        )
        #expect(prompt.contains("사용자 가이드"))
        #expect(prompt.contains(guide))
    }

    @Test func categoriesAppearInPromptAsQuotedCommaSeparatedList() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["식비", "구독", "통신"]
        )
        // Quotes delimit labels containing dots or separators
        #expect(prompt.contains("\"식비\", \"구독\", \"통신\""))
        #expect(prompt.contains("목록 밖 단어 금지"))
    }

    @Test func customCategoriesUsedInExampleWhenShoppingMissing() {
        // Fallback to first label if no keyword match
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["구독", "통신"]
        )
        #expect(prompt.contains("category=\"구독\""))
        #expect(!prompt.contains("category=\"쇼핑\""))
    }

    @Test func prefixedCategoriesPickMatchByKeywordInsteadOfFirst() {
        // Category prompt preserves labels with numerical prefixes
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: [
                "0. 고정비", "1. 교통", "2. 데이트", "3. 식비",
                "4. 생활・쇼핑", "5. 여가・취미", "6. 건강・의료", "7. 기타",
            ]
        )
        #expect(prompt.contains("category=\"3. 식비\""))
        #expect(prompt.contains("category=\"4. 생활・쇼핑\""))
        #expect(!prompt.contains("category=\"0. 고정비\""))
    }

    @Test func instructionsWarnAgainstPrefixStrippingAndDefaultFallback() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // Preserve numerical prefixes as part of label
        #expect(prompt.contains("접두 번호"))
        // Warn against defaulting to first category label
        #expect(prompt.contains("첫 번째 라벨을 기본값으로 쓰지 마세요"))
    }

    @Test func emptyCategoriesForceBlankCategory() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: []
        )
        #expect(prompt.contains("항상 빈 문자열로 두세요"))
        #expect(prompt.contains("category=\"\""))
    }

    @Test func instructionsExplainMultiTransactionRule() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("transactions"))
        #expect(prompt.contains("여러 행"))
        #expect(prompt.contains("transaction"))
    }

    @Test func instructionsForbidSummingDuplicateTotalLines() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // Do not sum repeated total lines
        #expect(prompt.contains("절대 더하지 마세요"))
    }

    @Test func instructionsRecognizeApprovalPatternVariants() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // Card payment notification approval pattern
        #expect(prompt.contains("일반승인"))
    }

    @Test func instructionsExcludeCashierAndPaymentMethodFromMerchant() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // Exclude cashier names and bracketed payment methods from merchant
        #expect(prompt.contains("캐셔"))
        #expect(prompt.contains("대괄호"))
    }

    @Test func instructionsNormalizeVariousDateFormats() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("YYYY.MM.DD"))
        #expect(prompt.contains("YYYY/MM/DD"))
    }

    @Test func instructionsWarnAgainstCopyingExampleData() {
        // Prevent copying example line items
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("예시 데이터를 복사하지"))
        #expect(prompt.contains("가짜 데이터"))
    }

    @Test func instructionsUsePlaceholderTokensNotRealBrands() {
        // Prompt examples must only use explicit placeholder tokens
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
        // Ensure Apple is not used as an example merchant
        #expect(!prompt.contains("merchant=\"Apple\""))
    }

    @Test func instructionsForbidNonZeroAmountWhenPriceVisible() {
        // Prevent zero amounts when payment amount is visible
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("amount는 0 금지"))
    }

    @Test func instructionsEmphasizeOneTransactionPerReceipt() {
        // Single transaction for receipt with items in array
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("transaction 정확히 1개"))
    }

    @Test func instructionsBrieflyMentionCardIssuerHeaderIsNotMerchant() {
        // Header cards are not separate transactions
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("카드사명"))
        #expect(prompt.contains("별도 transaction 아님"))
    }

    // MARK: - normalize() post-processing

    @Test func normalizeStripsCardIssuerMerchant() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 5000, merchant: "현대카드",
                category: "1. 교통", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions[0].merchant.isEmpty)
        #expect(out.transactions[0].amount == 5000)
    }

    @Test func normalizeStripsCardIssuerBrandVariants() {
        // Prefix match for card issuer variants
        let variants = [
            "현대카드Z",
            "현대카드M",
            "현대카드Z work",
            "현대카드 Z work 승인",
            "신한카드 The Mileage",
            "삼성카드 taptap",
            "KB국민카드 노리체크",
        ]
        for variant in variants {
            let input = PaymentExtraction(transactions: [
                PaymentTransaction(
                    date: "2026-05-18", amount: 5000, merchant: variant,
                    category: "", items: []
                ),
            ])
            let out = FoundationModelsExtractionService.normalize(input)
            #expect(out.transactions[0].merchant.isEmpty,
                    "\(variant) should be stripped as a card issuer variant")
        }
    }

    @Test func normalizeStripsCardIssuerMerchantWithSurroundingWhitespace() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 1000, merchant: "  신한카드 ",
                category: "", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions[0].merchant.isEmpty)
    }

    @Test func normalizeNaverPaymentProvidersToKorean() {
        let cases: [(input: String, expected: String)] = [
            ("NAVER FINANCIAL", "네이버페이"),
            ("NAVER PAY", "네이버페이"),
            ("Naver Pay", "네이버페이"),
            ("naverpay", "네이버페이"),
            ("네이버파이낸셜", "네이버페이"),
        ]
        for testCase in cases {
            let input = PaymentExtraction(transactions: [
                PaymentTransaction(
                    date: "2026-04-05", amount: 19600, merchant: testCase.input,
                    category: "", items: []
                ),
            ])
            let out = FoundationModelsExtractionService.normalize(input)
            #expect(out.transactions[0].merchant == testCase.expected,
                    "\(testCase.input) → \(testCase.expected)")
        }
    }

    @Test func normalizeKakaoAndTossPaymentProviders() {
        let cases: [(input: String, expected: String)] = [
            ("KAKAOPAY", "카카오페이"),
            ("Kakao Pay", "카카오페이"),
            ("토스페이먼츠", "토스페이"),
            ("TossPayments", "토스페이"),
        ]
        for testCase in cases {
            let input = PaymentExtraction(transactions: [
                PaymentTransaction(
                    date: "2026-05-01", amount: 1000, merchant: testCase.input,
                    category: "", items: []
                ),
            ])
            let out = FoundationModelsExtractionService.normalize(input)
            #expect(out.transactions[0].merchant == testCase.expected,
                    "\(testCase.input) → \(testCase.expected)")
        }
    }

    @Test func normalizeLeavesGenuineMerchantUnchanged() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-16", amount: 10700, merchant: "투썸플레이스",
                category: "3. 식비",
                items: [PaymentLineItem(name: "아메리카노", amount: 4500)]
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions[0].merchant == "투썸플레이스")
        #expect(out.transactions[0].category == "3. 식비")
        #expect(out.transactions[0].items.count == 1)
    }

    @Test func normalizePreservesEmptyMerchant() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-01", amount: 0, merchant: "",
                category: "", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions[0].merchant.isEmpty)
    }

    @Test func normalizePreservesMultipleTransactions() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 5000, merchant: "현대카드",
                category: "", items: []
            ),
            PaymentTransaction(
                date: "2026-05-18", amount: 1500, merchant: "다이소",
                category: "4. 생활・쇼핑", items: []
            ),
            PaymentTransaction(
                date: "2026-04-05", amount: 19600, merchant: "NAVER PAY",
                category: "", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.count == 3)
        #expect(out.transactions[0].merchant.isEmpty)
        #expect(out.transactions[1].merchant == "다이소")
        #expect(out.transactions[2].merchant == "네이버페이")
    }

    @Test func paymentExtractionEquatesByValue() {
        let a = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000, merchant: "X",
                category: "카페", items: [PaymentLineItem(name: "아메리카노", amount: 5000)]
            ),
        ])
        let b = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000, merchant: "X",
                category: "카페", items: [PaymentLineItem(name: "아메리카노", amount: 5000)]
            ),
        ])
        let c = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000, merchant: "X",
                category: "카페", items: []
            ),
        ])
        #expect(a == b)
        #expect(a != c)
    }
}
