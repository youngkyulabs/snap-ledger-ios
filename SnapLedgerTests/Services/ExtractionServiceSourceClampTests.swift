import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ExtractionServiceSourceClampTests {
    private let base = InboxPayload.extractionCharacterLimit

    @Test func baselineContextKeepsBaseLimit() {
        let limit = FoundationModelsExtractionService.sourceCharacterLimit(
            contextSize: FoundationModelsExtractionService.baselineContextSize
        )

        #expect(limit == base)
    }

    @Test func largerContextScalesLimit() {
        let limit = FoundationModelsExtractionService.sourceCharacterLimit(contextSize: 8_192)

        #expect(limit == base * 2)
    }

    @Test func smallerOrMissingContextKeepsBaseLimit() {
        #expect(FoundationModelsExtractionService.sourceCharacterLimit(contextSize: 0) == base)
        #expect(FoundationModelsExtractionService.sourceCharacterLimit(contextSize: 2_048) == base)
    }

    @Test func shortTextIsUnchanged() {
        let text = "예시상호 2026-05-17\n합계 7,777"

        #expect(FoundationModelsExtractionService.clampSourceText(text, limit: 100) == text)
    }

    @Test func textAtLimitIsUnchanged() {
        let text = String(repeating: "가", count: 100)

        #expect(FoundationModelsExtractionService.clampSourceText(text, limit: 100) == text)
    }

    @Test func longTextKeepsHeadAndTailWithinLimit() {
        let header = "예시상호 2026-05-17"
        let footer = "합계 7,777\n승인번호 12345678"
        let items = (1...300).map { "예시품목\($0) 1,000" }.joined(separator: "\n")
        let text = "\(header)\n\(items)\n\(footer)"

        let clamped = FoundationModelsExtractionService.clampSourceText(text, limit: 200)

        #expect(clamped.count == 200)
        #expect(clamped.hasPrefix(header))
        #expect(clamped.hasSuffix(footer))
    }
}
