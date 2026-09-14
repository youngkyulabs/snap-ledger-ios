// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Verifies year normalization for parsed dates.
@MainActor
struct ExtractionServiceYearNormalizationTests {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: .init(identifier: .gregorian),
            year: year, month: month, day: day
        ).date!
    }

    @Test func normalizeYearKeepsRecentPastUntouched() {
        // Past date within same week remains unchanged.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-05-23", today: today
        )
        #expect(out == "2026-05-23")
    }

    @Test func normalizeYearShiftsImpossibleFutureBackOneYear() {
        // Dates > 2 days in future adjust -1 year.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2027-05-24", today: today
        )
        #expect(out == "2026-05-24")
    }

    @Test func normalizeYearShiftsPriorYearForwardWhenNearlyAYearOld() {
        // Dates < -330 days in past adjust +1 year.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2025-05-26", today: today
        )
        #expect(out == "2026-05-26")
    }

    @Test func normalizeYearAllowsSmallFutureSlackForTimezone() {
        // 1-2 days in future tolerated for timezone slack.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-05-27", today: today
        )
        #expect(out == "2026-05-27")
    }

    @Test func normalizeYearAllowsModeratelyOldDates() {
        // Normal past dates remain unchanged.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-04-15", today: today
        )
        #expect(out == "2026-04-15")
    }

    @Test func normalizeYearPreservesEmptyAndWhitespace() {
        let today = makeDate(year: 2026, month: 5, day: 25)
        #expect(FoundationModelsExtractionService.normalizeYear("", today: today).isEmpty)
        // Empty trimmed string returns raw value.
        #expect(FoundationModelsExtractionService.normalizeYear("   ", today: today) == "   ")
    }

    @Test func normalizeYearLeavesUnparseableStringAlone() {
        let today = makeDate(year: 2026, month: 5, day: 25)
        let invalid = ["abc", "2026", "2026-13-01", "2026-05-99", "5/24"]
        for raw in invalid {
            let out = FoundationModelsExtractionService.normalizeYear(raw, today: today)
            #expect(out == raw, "Unparseable '\(raw)' should be returned unchanged")
        }
    }

    @Test func normalizeYearAcceptsSlashAndDotSeparators() {
        // Non-standard delimiters normalized properly.
        let today = makeDate(year: 2026, month: 5, day: 25)
        #expect(FoundationModelsExtractionService.normalizeYear(
            "2025/05/26", today: today) == "2026-05-26")
        #expect(FoundationModelsExtractionService.normalizeYear(
            "2025.05.26", today: today) == "2026-05-26")
    }

    @Test func normalizeAppliesYearCorrectionInsideTransactions() {
        let today = makeDate(year: 2026, month: 5, day: 25)
        let input = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2025-05-26", amount: 1000, merchant: "다이소",
                category: "", items: []
            ),
        ])
        let out = FoundationModelsExtractionService.normalize(input, today: today)
        #expect(out.transactions[0].date == "2026-05-26")
        #expect(out.transactions[0].merchant == "다이소")
    }
}
