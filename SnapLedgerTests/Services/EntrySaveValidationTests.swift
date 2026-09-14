import Testing
@testable import SnapLedger

@MainActor
struct EntrySaveValidationTests {
    // MARK: - Review Entry Save (Blocks 0 amount)

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

    // MARK: - History Entry Save (Allows 0 amount, blocks negative)

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
