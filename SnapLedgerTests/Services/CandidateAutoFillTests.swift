import Testing
@testable import SnapLedger

@MainActor
struct CandidateAutoFillTests {
    // MARK: - Merchant: First Candidate If Empty

    @Test func merchantEmptyFillsFromFirstCandidate() {
        #expect(CandidateAutoFill.merchant(current: "", candidates: ["스타벅스", "투썸"]) == "스타벅스")
    }

    @Test func merchantEmptyWithNoCandidatesStaysEmpty() {
        #expect(CandidateAutoFill.merchant(current: "", candidates: []).isEmpty)
    }

    @Test func merchantNonEmptyKeepsCurrent() {
        #expect(CandidateAutoFill.merchant(current: "내가입력", candidates: ["스타벅스"]) == "내가입력")
    }

    // MARK: - Amount: Filled Only When Single Candidate Exists

    @Test func amountZeroWithSingleCandidateFills() {
        #expect(CandidateAutoFill.amount(current: 0, candidates: [5000]) == 5000)
    }

    @Test func amountZeroWithMultipleCandidatesStaysZero() {
        #expect(CandidateAutoFill.amount(current: 0, candidates: [5000, 10000]) == 0)
    }

    @Test func amountZeroWithNoCandidatesStaysZero() {
        #expect(CandidateAutoFill.amount(current: 0, candidates: []) == 0)
    }

    @Test func amountNonZeroKeepsCurrent() {
        #expect(CandidateAutoFill.amount(current: 3000, candidates: [5000]) == 3000)
    }

    // MARK: - Category: Prefer Learned In Presets Over Extracted

    @Test func categoryPrefersValidLearnedOverExtraction() {
        let out = CandidateAutoFill.category(
            learned: "카페", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "카페")
    }

    @Test func categoryDropsOffPresetLearnedAndFallsBackToExtraction() {
        // Fallback to extracted category if learned category is outside presets.
        let out = CandidateAutoFill.category(
            learned: "옛카테고리", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "식비")
    }

    @Test func categoryReturnsNilWhenLearnedOffPresetAndNoExtraction() {
        let out = CandidateAutoFill.category(
            learned: "옛카테고리", extracted: nil, presets: AppSettings.defaultPresets
        )
        #expect(out == nil)
    }

    @Test func categoryUsesExtractionWhenNoLearned() {
        let out = CandidateAutoFill.category(
            learned: nil, extracted: "카페", presets: AppSettings.defaultPresets
        )
        #expect(out == "카페")
    }

    @Test func categoryTreatsBlankLearnedAsAbsent() {
        let out = CandidateAutoFill.category(
            learned: "   ", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "식비")
    }

    @Test func categoryTrimsValidLearnedValue() {
        // Trimmed comparison for category matching.
        let out = CandidateAutoFill.category(
            learned: " 카페 ", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "카페")
    }
}
