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
        // 따옴표로 감싸야 라벨 안의 점·구분 기호와 콤마가 헷갈리지 않음
        #expect(prompt.contains("\"식비\", \"구독\", \"통신\""))
        #expect(prompt.contains("목록 밖 단어 금지"))
    }

    @Test func customCategoriesUsedInExampleWhenShoppingMissing() {
        // "쇼핑"/"생활" 키워드도 부분 일치하는 라벨이 없으면 첫 항목으로 폴백
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["구독", "통신"]
        )
        #expect(prompt.contains("category=\"구독\""))
        #expect(!prompt.contains("category=\"쇼핑\""))
    }

    @Test func prefixedCategoriesPickMatchByKeywordInsteadOfFirst() {
        // 사용자가 정렬용 접두 번호("0. 고정비", "1. 교통" …)를 붙여도
        // 예시 카테고리가 항상 첫 라벨("0. 고정비")로 떨어지지 않아야 함.
        // 카페/식비 영수증 예시는 "3. 식비"로, 쇼핑/생활 알림 예시는 "4. 생활・쇼핑"으로.
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
        // 접두 번호를 라벨의 일부로 인식해 함께 복사
        #expect(prompt.contains("접두 번호"))
        // 잘 모르겠다고 첫 번째 라벨을 기본값으로 쓰지 않도록 경고
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
        // 합산 라인 중복 시 한 번만 — 합산 금지
        #expect(prompt.contains("절대 더하지 마세요"))
    }

    @Test func instructionsRecognizeApprovalPatternVariants() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // 현대카드 결제 내역 리스트의 "5,000원 · 일반승인" 패턴 인식
        #expect(prompt.contains("일반승인"))
    }

    @Test func instructionsExcludeCashierAndPaymentMethodFromMerchant() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        // 캐셔/서명 이름·대괄호 결제수단 표기는 merchant 아님
        // (구체적 PG·카드사 strip은 normalize() 책임, 별도 테스트로 검증)
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
        // FM이 예시의 "아메리카노 T 4,500" 같은 데이터를 응답에 복사하던 환각 방지
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("예시 데이터를 복사하지"))
        #expect(prompt.contains("가짜 데이터"))
    }

    @Test func instructionsUsePlaceholderTokensNotRealBrands() {
        // 모델이 예시를 베껴 출력하던 케이스를 막기 위해, 예시 블록은
        // 명백한 가짜 토큰('예시상호N', '예시품목N')만 사용해야 한다.
        // 실제 상호명("스타벅스", "쿠팡", "Apple") 또는 실제 품목명("아메리카노",
        // "카페라떼")이 prompt에 들어가면 환각 위험이 다시 생긴다.
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
        // "Apple" 단어는 짧고 일반적이라 다른 룰에 들어갈 수 있으니
        // 예시 머천트로는 안 쓴다는 의미로 정확한 매치만 확인.
        #expect(!prompt.contains("merchant=\"Apple\""))
    }

    @Test func instructionsForbidNonZeroAmountWhenPriceVisible() {
        // 푸시 알림에서 amount=0으로 떨어지던 문제 방지
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("amount는 0 금지"))
    }

    @Test func instructionsEmphasizeOneTransactionPerReceipt() {
        // 영수증을 품목별로 split하던 환각 방지
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now, customGuide: "", categories: defaultCategories
        )
        #expect(prompt.contains("transaction 정확히 1개"))
    }

    @Test func instructionsBrieflyMentionCardIssuerHeaderIsNotMerchant() {
        // prompt 단순화 후 — 카드사 prefix·PG 정규화는 normalize() 책임,
        // prompt는 짧게만 언급. 카드사명 헤더 = 별도 transaction 아님 안내만 유지.
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
        // 현대카드Z, 현대카드M, 현대카드 Z work 승인 등 prefix 매칭
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
