// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Verifies year resolution when OCR text states no year.
@MainActor
struct ExtractionServiceYearSnapTests {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: .init(identifier: .gregorian),
            year: year, month: month, day: day
        ).date!
    }

    private func transaction(date: String) -> PaymentExtraction {
        PaymentExtraction(transactions: [
            PaymentTransaction(date: date, amount: 5000, merchant: "스타벅스", category: "", items: []),
        ])
    }

    // MARK: - hasExplicitYear

    @Test func explicitYearDetectsFullDates() {
        #expect(FoundationModelsExtractionService.hasExplicitYear("2026-09-13 15:30 승인"))
        #expect(FoundationModelsExtractionService.hasExplicitYear("2026.09.13 결제"))
        #expect(FoundationModelsExtractionService.hasExplicitYear("2026/09/13"))
        #expect(FoundationModelsExtractionService.hasExplicitYear("2026년 9월 13일"))
    }

    @Test func explicitYearIgnoresAmountsAndTimes() {
        // Four-digit runs without a date separator must not read as a year.
        #expect(!FoundationModelsExtractionService.hasExplicitYear("09/13 20:26 스타벅스 2026원 승인"))
        #expect(!FoundationModelsExtractionService.hasExplicitYear("일시불 20,260원"))
        #expect(!FoundationModelsExtractionService.hasExplicitYear("1234-5678-9012-3456"))
    }

    @Test func explicitYearIgnoresAccountAndPhoneNumbers() {
        // Hyphenated identifiers must not be read as YYYY-MM-DD.
        #expect(!FoundationModelsExtractionService.hasExplicitYear("국민 123456-78-901234 입금"))
        #expect(!FoundationModelsExtractionService.hasExplicitYear("우리 1002-123-456789"))
        #expect(!FoundationModelsExtractionService.hasExplicitYear("031-1234-5678"))
    }

    @Test func normalizeSnapsYearWhenTextOnlyCarriesAnAccountNumber() {
        // The account number must not suppress snapping for a text that states no year.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.normalize(
            transaction(date: "2024-09-13"),
            today: today,
            ocrText: "국민 123456-78-901234 09/13 15:30 스타벅스 5,000원 승인"
        )
        #expect(out.transactions[0].date == "2026-09-13")
    }

    // MARK: - snapYearToNearest

    @Test func snapUsesCurrentYearForRecentPast() {
        // Model filled a training-distribution year; month/day are the only signal.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.snapYearToNearest("2024-09-13", today: today)
        #expect(out == "2026-09-13")
    }

    @Test func snapRollsBackWhenCurrentYearWouldBeFuture() {
        // Late-December payment read in early January belongs to the prior year.
        let today = makeDate(year: 2026, month: 1, day: 5)
        let out = FoundationModelsExtractionService.snapYearToNearest("2023-12-28", today: today)
        #expect(out == "2025-12-28")
    }

    @Test func snapAllowsTwoDayFutureSlack() {
        // Timezone skew may place a fresh payment slightly ahead of local today.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.snapYearToNearest("2020-09-16", today: today)
        #expect(out == "2026-09-16")
    }

    @Test func snapRollsBackBeyondSlackWindow() {
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.snapYearToNearest("2026-11-05", today: today)
        #expect(out == "2025-11-05")
    }

    @Test func snapLeavesUnparseableStringAlone() {
        let today = makeDate(year: 2026, month: 9, day: 15)
        for raw in ["abc", "2026", "2026-13-01", "5/24", ""] {
            #expect(FoundationModelsExtractionService.snapYearToNearest(raw, today: today) == raw)
        }
    }

    @Test func snapRejectsDayInvalidForSnappedYear() {
        // 2/29 cannot move to a non-leap year, so the raw value stays untouched.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.snapYearToNearest("2024-02-29", today: today)
        #expect(out == "2024-02-29")
    }

    // MARK: - normalize integration

    @Test func normalizeSnapsYearWhenOCRTextHasNoYear() {
        // Reproduces the reported bug: notification shows only MM/DD, model invents a past year.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.normalize(
            transaction(date: "2024-09-13"),
            today: today,
            ocrText: "09/13 15:30 스타벅스 5,000원 일시불 승인"
        )
        #expect(out.transactions[0].date == "2026-09-13")
    }

    @Test func normalizeTrustsExplicitYearInOCRText() {
        // A stated year may legitimately be old (scanned receipt) and must survive.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.normalize(
            transaction(date: "2026-03-02"),
            today: today,
            ocrText: "2026-03-02 스타벅스 5,000원 승인"
        )
        #expect(out.transactions[0].date == "2026-03-02")
    }

    @Test func normalizeWithoutOCRTextKeepsLegacyBehavior() {
        // No OCR context available: fall back to the ±1 year correction.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let out = FoundationModelsExtractionService.normalize(
            transaction(date: "2026-04-01"),
            today: today
        )
        #expect(out.transactions[0].date == "2026-04-01")
    }
}
