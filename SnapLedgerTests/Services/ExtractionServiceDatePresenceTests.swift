// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// OCR 원문에 날짜 표기가 전혀 없으면 모델이 지어낸 date를 버리고 빈 문자열로 둔다
/// (→ 다운스트림에서 오늘로 폴백). normalizeYear는 연도만 보정할 뿐 통째로 환각한
/// 월·일은 못 걸러내므로, "원문에 날짜 토큰 없음"이라는 결정적 근거로 사후 차단한다.
@MainActor
struct ExtractionServiceDatePresenceTests {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: .init(identifier: .gregorian),
            year: year, month: month, day: day
        ).date!
    }

    // MARK: - hasDateToken

    @Test func detectsFullDateFormats() {
        #expect(FoundationModelsExtractionService.hasDateToken("결제일 2026-05-17 승인"))
        #expect(FoundationModelsExtractionService.hasDateToken("2026/05/17"))
        #expect(FoundationModelsExtractionService.hasDateToken("2026.05.17"))
    }

    @Test func detectsPartialMonthDayFormats() {
        #expect(FoundationModelsExtractionService.hasDateToken("5/17 스타벅스 4,500원 일시불"))
        #expect(FoundationModelsExtractionService.hasDateToken("현대카드 5.17 일시불"))
    }

    /// 영수증에 흔한 한국식 표기(년/월/일). 예전엔 -./만 인식해 이 날짜가 통째로
    /// 버려지고 오늘로 폴백됐다 — 진짜 날짜를 지우던 회귀를 막는다.
    @Test func detectsKoreanDateNotation() {
        #expect(FoundationModelsExtractionService.hasDateToken("2026년 5월 17일 스타벅스 4,500원"))
        #expect(FoundationModelsExtractionService.hasDateToken("2026년 05월 17일"))
        #expect(FoundationModelsExtractionService.hasDateToken("5월 17일 승인"))
        #expect(FoundationModelsExtractionService.hasDateToken("5월17일"))
    }

    @Test func reportsNoDateWhenAbsent() {
        // 금액·시간만 있고 날짜 표기가 없는 경우.
        #expect(!FoundationModelsExtractionService.hasDateToken("스타벅스 아메리카노 4,500원 일시불 승인"))
        #expect(!FoundationModelsExtractionService.hasDateToken("합계 12,000원 부가세 1,090원"))
        #expect(!FoundationModelsExtractionService.hasDateToken("현대카드 결제 14:32 승인"))
    }

    /// 소수·비율은 날짜가 아니다 — 월(1–12)·일(1–31) 범위를 벗어나는 값은 걸러
    /// 환각 가드가 우연한 숫자에 무력화되지 않도록 한다.
    @Test func rejectsOutOfRangeDecimalsAsDates() {
        #expect(!FoundationModelsExtractionService.hasDateToken("부가세율 10.0%"))   // 일 0
        #expect(!FoundationModelsExtractionService.hasDateToken("재고 13.5 개"))      // 월 13
        #expect(!FoundationModelsExtractionService.hasDateToken("10.50 kg"))         // 일 50
    }

    // MARK: - normalize 날짜 드롭 가드

    @Test func normalizeBlanksHallucinatedDateWhenOCRHasNoDateToken() {
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2024-03-15", amount: 4500, merchant: "스타벅스",
                category: "카페", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(
            input, ocrText: "스타벅스 아메리카노 4,500원 일시불 승인"
        )
        #expect(out.transactions.first?.date.isEmpty == true)
    }

    @Test func normalizeKeepsDateWhenOCRHasDateToken() {
        let today = makeDate(year: 2026, month: 5, day: 20)
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 4500, merchant: "스타벅스",
                category: "카페", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(
            input, today: today, ocrText: "2026-05-17 스타벅스 4,500원"
        )
        #expect(out.transactions.first?.date == "2026-05-17")
    }

    @Test func normalizeWithoutOCRTextSkipsDateGuard() {
        // ocrText 미제공(기존 호출부)은 가드를 건너뛰고 normalizeYear만 적용.
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 4500, merchant: "스타벅스",
                category: "카페", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input)
        #expect(out.transactions.first?.date == "2026-05-17")
    }
}
