import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ReviewAmountInputTests {
    private func makeEntry(amount: Int = 0) -> ParsedEntry {
        ParsedEntry(date: .now, amount: amount, merchant: "스타벅스")
    }

    @Test func untypedZeroShowsEmptyAndBlocksSave() {
        let entry = makeEntry()
        #expect(ReviewAmountInput.displayValue(for: entry) == nil)
        #expect(!EntrySaveValidation.canSaveReview(entry))
    }

    @Test func typedZeroShowsZeroAndAllowsSave() {
        let entry = makeEntry()
        ReviewAmountInput.apply(0, to: entry)
        #expect(entry.amount == 0)
        #expect(entry.amountEntered)
        #expect(ReviewAmountInput.displayValue(for: entry) == 0)
        #expect(EntrySaveValidation.canSaveReview(entry))
    }

    @Test func clearingTypedZeroBlocksSaveAgain() {
        let entry = makeEntry()
        ReviewAmountInput.apply(0, to: entry)
        ReviewAmountInput.apply(nil, to: entry)
        #expect(entry.amount == 0)
        #expect(!entry.amountEntered)
        #expect(ReviewAmountInput.displayValue(for: entry) == nil)
        #expect(!EntrySaveValidation.canSaveReview(entry))
    }

    @Test func extractedPositiveAmountShowsWithoutTyping() {
        let entry = makeEntry(amount: 5000)
        #expect(ReviewAmountInput.displayValue(for: entry) == 5000)
        #expect(EntrySaveValidation.canSaveReview(entry))
    }

    @Test func typedPositiveAmountIsStored() {
        let entry = makeEntry()
        ReviewAmountInput.apply(12000, to: entry)
        #expect(entry.amount == 12000)
        #expect(EntrySaveValidation.canSaveReview(entry))
    }
}
