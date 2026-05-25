// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// `normalizeYear` 후처리에 대한 테스트.
/// 모델이 instructions의 "오늘의 연도" 규칙을 무시하고 학습 분포의 이전 연도로
/// 채우는 환각을, "결제 시점 ≈ 추출 시점" invariant로 사후 보정한다.
@MainActor
struct ExtractionServiceYearNormalizationTests {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: .init(identifier: .gregorian),
            year: year, month: month, day: day
        ).date!
    }

    @Test func normalizeYearKeepsRecentPastUntouched() {
        // 오늘이 2026-05-25일 때 같은 주의 과거 날짜는 그대로 둔다.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-05-23", today: today
        )
        #expect(out == "2026-05-23")
    }

    @Test func normalizeYearShiftsImpossibleFutureBackOneYear() {
        // 모델이 "5/24" → "2027-05-24"로 환각하면 1년+ 미래.
        // 카드 알림은 미래일 수 없으므로 -1년 보정.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2027-05-24", today: today
        )
        #expect(out == "2026-05-24")
    }

    @Test func normalizeYearShiftsPriorYearForwardWhenNearlyAYearOld() {
        // 모델이 "5/26" → "2025-05-26"으로 채우면 거의 1년 전. +1년 보정.
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2025-05-26", today: today
        )
        #expect(out == "2026-05-26")
    }

    @Test func normalizeYearAllowsSmallFutureSlackForTimezone() {
        // 1~2일 미래는 timezone 슬랙으로 허용 (보정 없음).
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-05-27", today: today
        )
        #expect(out == "2026-05-27")
    }

    @Test func normalizeYearAllowsModeratelyOldDates() {
        // 한 달 전 같은 보통의 과거는 보정하지 않는다 (사용자가 늦게 처리할 수 있음).
        let today = makeDate(year: 2026, month: 5, day: 25)
        let out = FoundationModelsExtractionService.normalizeYear(
            "2026-04-15", today: today
        )
        #expect(out == "2026-04-15")
    }

    @Test func normalizeYearPreservesEmptyAndWhitespace() {
        let today = makeDate(year: 2026, month: 5, day: 25)
        #expect(FoundationModelsExtractionService.normalizeYear("", today: today).isEmpty)
        // trim 결과가 비면 raw 그대로 리턴 (공백 보존)
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
        // 모델이 instructions를 무시하고 비표준 구분자를 줘도 후처리는 동작.
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
