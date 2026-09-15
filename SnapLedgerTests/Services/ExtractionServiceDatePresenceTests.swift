// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Verifies dropping hallucinated dates when OCR text has no date token.
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

    /// Korean date format tokens are recognized.
    @Test func detectsKoreanDateNotation() {
        #expect(FoundationModelsExtractionService.hasDateToken("2026년 5월 17일 스타벅스 4,500원"))
        #expect(FoundationModelsExtractionService.hasDateToken("2026년 05월 17일"))
        #expect(FoundationModelsExtractionService.hasDateToken("5월 17일 승인"))
        #expect(FoundationModelsExtractionService.hasDateToken("5월17일"))
    }

    @Test func reportsNoDateWhenAbsent() {
        // Text containing time and amount but no date.
        #expect(!FoundationModelsExtractionService.hasDateToken("스타벅스 아메리카노 4,500원 일시불 승인"))
        #expect(!FoundationModelsExtractionService.hasDateToken("합계 12,000원 부가세 1,090원"))
        #expect(!FoundationModelsExtractionService.hasDateToken("현대카드 결제 14:32 승인"))
    }

    /// Decimals and ratios outside calendar ranges are not treated as dates.
    @Test func rejectsOutOfRangeDecimalsAsDates() {
        #expect(!FoundationModelsExtractionService.hasDateToken("부가세율 10.0%"))   // Day 0
        #expect(!FoundationModelsExtractionService.hasDateToken("재고 13.5 개"))      // Month 13
        #expect(!FoundationModelsExtractionService.hasDateToken("10.50 kg"))         // Day 50
    }

    // MARK: - Normalize Date Drop Guard

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
        // Normalize applies year correction only when ocrText is omitted.
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
