import Testing
@testable import SnapLedger

@MainActor
struct CandidateAutoFillTests {
    // MARK: - 설명(가맹점): 비면 첫 후보, 아니면 유지

    @Test func merchantEmptyFillsFromFirstCandidate() {
        #expect(CandidateAutoFill.merchant(current: "", candidates: ["스타벅스", "투썸"]) == "스타벅스")
    }

    @Test func merchantEmptyWithNoCandidatesStaysEmpty() {
        #expect(CandidateAutoFill.merchant(current: "", candidates: []).isEmpty)
    }

    @Test func merchantNonEmptyKeepsCurrent() {
        #expect(CandidateAutoFill.merchant(current: "내가입력", candidates: ["스타벅스"]) == "내가입력")
    }

    // MARK: - 금액: 0이고 후보가 정확히 1개일 때만 채움

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

    // MARK: - 카테고리: 학습값이 현재 프리셋 안일 때만 우선, 아니면 추출값으로

    @Test func categoryPrefersValidLearnedOverExtraction() {
        let out = CandidateAutoFill.category(
            learned: "카페", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "카페")
    }

    @Test func categoryDropsOffPresetLearnedAndFallsBackToExtraction() {
        // 프리셋에서 지운 옛 카테고리는 자동채움에서 되살리지 않고 추출값으로.
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
        // 학습 저장은 카테고리를 trim하지 않으므로, 공백 낀 유효 학습값도
        // 프리셋과 일치로 판정되고 trim된 값으로 반환돼야 한다.
        let out = CandidateAutoFill.category(
            learned: " 카페 ", extracted: "식비", presets: AppSettings.defaultPresets
        )
        #expect(out == "카페")
    }
}
