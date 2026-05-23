import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct CandidateHeuristicsTests {
    @Test func amountsExtractsBasicAmounts() {
        let ocr = "투썸플레이스 / 5,000원 일시불, 5/18 19:56 / 합계 10,700원"
        #expect(CandidateHeuristics.amounts(from: ocr) == [5000, 10700])
    }

    @Test func amountsExcludesAccumulatedLine() {
        let ocr = "현대카드\n5,000원 일시불\n투썸플레이스\n누적530,248원"
        #expect(CandidateHeuristics.amounts(from: ocr) == [5000])
    }

    @Test func amountsExcludesVATAndTax() {
        let ocr = "총액 10,700  부가세 973  과세물품가액 9,727  결제금액 10,700"
        #expect(CandidateHeuristics.amounts(from: ocr) == [10700])
    }

    @Test func amountsExcludesZero() {
        #expect(CandidateHeuristics.amounts(from: "0원 결제 5,000원 일시불") == [5000])
    }

    @Test func amountsCapsAtFive() {
        let ocr = (1...8).map { "\($0 * 1000)원" }.joined(separator: " / ")
        #expect(CandidateHeuristics.amounts(from: ocr).count == 5)
    }

    // MARK: - merchants

    @Test func merchantsExcludesCardIssuer() {
        let ocr = "현대카드\n5,000원 일시불, 5/18 19:56\n투썸플레이스강남자곡점\n누적530,248원"
        #expect(CandidateHeuristics.merchants(from: ocr) == ["투썸플레이스강남자곡점"])
    }

    @Test func merchantsExcludesAmountAndDateLines() {
        let ocr = "투썸플레이스\n2026/05/16 20:38\n5,700원\n총액 10,700"
        #expect(CandidateHeuristics.merchants(from: ocr) == ["투썸플레이스"])
    }

    @Test func merchantsExcludesBookkeepingKeywords() {
        let ocr = """
        A TWOSOME PLACE
        POS:01-030803405
        주문번호 901
        캐셔 홍길동
        [네이버페이 카드]
        승인
        """
        #expect(CandidateHeuristics.merchants(from: ocr) == ["A TWOSOME PLACE"])
    }

    @Test func merchantsCapsAtFive() {
        let ocr = (1...8).map { "매장이름\($0)점" }.joined(separator: "\n")
        #expect(CandidateHeuristics.merchants(from: ocr).count == 5)
    }

    // MARK: - enrich

    @Test func enrichMergesFMBestWithHeuristics() {
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 5000, merchant: "투썸플레이스강남자곡점",
                category: "", items: []
            ),
        ])
        let ocr = "현대카드\n5,000원 일시불, 5/18 19:56\n투썸플레이스강남자곡점\n누적530,248원"
        let enriched = CandidateHeuristics.enrich(extraction, ocrText: ocr)
        #expect(enriched.count == 1)
        #expect(enriched[0].base.merchant == "투썸플레이스강남자곡점")
        #expect(enriched[0].merchantCandidates.first == "투썸플레이스강남자곡점")
        #expect(enriched[0].amountCandidates.first == 5000)
    }

    @Test func enrichDedupsBestIntoCandidates() {
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 10000, merchant: "스타벅스",
                category: "", items: []
            ),
        ])
        let ocr = "스타벅스\n10,000원\n부가세 909"
        let enriched = CandidateHeuristics.enrich(extraction, ocrText: ocr)
        #expect(enriched[0].merchantCandidates.filter { $0 == "스타벅스" }.count == 1)
        #expect(enriched[0].amountCandidates.filter { $0 == 10000 }.count == 1)
    }

    @Test func enrichSkipsBestWhenEmptyOrZero() {
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-18", amount: 0, merchant: "",
                category: "", items: []
            ),
        ])
        let ocr = "투썸플레이스\n5,000원 일시불"
        let enriched = CandidateHeuristics.enrich(extraction, ocrText: ocr)
        #expect(enriched[0].merchantCandidates == ["투썸플레이스"])
        #expect(enriched[0].amountCandidates == [5000])
    }

    // MARK: - payment signal gate

    @Test func paymentSignalDetectedFromKRWAmount() {
        #expect(CandidateHeuristics.hasPaymentSignal("투썸플레이스 5,000원 일시불"))
    }

    @Test func paymentSignalDetectedFromCommaThousands() {
        #expect(CandidateHeuristics.hasPaymentSignal("합계 10,700"))
    }

    @Test func paymentSignalDetectedFromWonSuffix() {
        #expect(CandidateHeuristics.hasPaymentSignal("3300원 결제"))
    }

    @Test func paymentSignalDetectedFromWonSymbol() {
        #expect(CandidateHeuristics.hasPaymentSignal("₩12,000"))
    }

    @Test func paymentSignalDetectedFromKRWPrefix() {
        #expect(CandidateHeuristics.hasPaymentSignal("KRW 25020"))
    }

    @Test func paymentSignalDetectedFromKeywordOnly() {
        // 푸시 알림에서 OCR이 금액을 놓치고 키워드만 남는 corner case
        #expect(CandidateHeuristics.hasPaymentSignal("결제 승인 일시불"))
    }

    @Test func noPaymentSignalInLandscapeOCRText() {
        // 풍경/문서 사진의 OCR 결과 — 금액·통화·결제 키워드 없음
        #expect(!CandidateHeuristics.hasPaymentSignal("바다와 노을 풍경 사진"))
        #expect(!CandidateHeuristics.hasPaymentSignal("Welcome to the conference"))
        #expect(!CandidateHeuristics.hasPaymentSignal(""))
        #expect(!CandidateHeuristics.hasPaymentSignal("   \n  \t "))
    }

    @Test func loneDigitsWithoutCurrencyAreNotPaymentSignal() {
        // 사진 메타데이터에 흔한 "2026 05 18", "12:34" 같은 노이즈는 신호로 잡지 않음
        #expect(!CandidateHeuristics.hasPaymentSignal("2026 05 18 12:34"))
    }
}
