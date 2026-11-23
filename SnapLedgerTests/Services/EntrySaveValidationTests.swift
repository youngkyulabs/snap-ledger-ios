import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct EntrySaveValidationTests {
    // MARK: - Review Entry Save (Blocks 0 amount unless typed)

    @Test func reviewRejectsEmptyMerchant() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "", amount: 5000, amountEntered: true))
    }

    @Test func reviewRejectsZeroAmountNotEntered() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: 0, amountEntered: false))
    }

    @Test func reviewAcceptsZeroAmountEntered() {
        #expect(EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: 0, amountEntered: true))
    }

    @Test func reviewRejectsNegativeAmount() {
        #expect(!EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: -1, amountEntered: true))
    }

    @Test func reviewAcceptsPositiveAmount() {
        #expect(EntrySaveValidation.canSaveReview(merchant: "스타벅스", amount: 5000, amountEntered: false))
    }

    @Test func parsedEntryStartsWithAmountNotEntered() {
        let entry = ParsedEntry(date: .now, amount: 0, merchant: "스타벅스")
        #expect(!entry.amountEntered)
        #expect(!EntrySaveValidation.canSaveReview(entry))
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
