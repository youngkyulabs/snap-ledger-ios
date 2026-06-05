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
}
