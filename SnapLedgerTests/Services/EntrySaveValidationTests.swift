import Testing
@testable import SnapLedger

@MainActor
struct EntrySaveValidationTests {
    // MARK: - 검토(추출 결과) 저장 — 0원 차단

    @Test func reviewRejectsEmptyMerchant() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "", amount: 5000))
    }

    @Test func reviewRejectsZeroAmount() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: 0))
    }

    @Test func reviewRejectsNegativeAmount() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: -1))
    }

    @Test func reviewAcceptsPositiveAmount() {
        #expect(EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: 5000))
    }

    // MARK: - 편집(기록 수정) 저장 — 0원 허용, 음수만 차단

    @Test func editRejectsEmptyMerchant() {
        #expect(!EntrySaveValidation.canSaveEdit(merchant: "", amount: 0))
    }

    @Test func editAcceptsZeroAmount() {
        #expect(EntrySaveValidation.canSaveEdit(merchant: "스타벅스", amount: 0))
    }

    @Test func editRejectsNegativeAmount() {
        #expect(!EntrySaveValidation.canSaveEdit(merchant: "스타벅스", amount: -1))
    }

    @Test func editAcceptsPositiveAmount() {
        #expect(EntrySaveValidation.canSaveEdit(merchant: "스타벅스", amount: 5000))
    }
}
