import Foundation

/// Validation helper for expense entries.
enum EntrySaveValidation {
    /// Validates review entry for saving (amount > 0, or 0 only when the user typed it).
    static func canSaveReview(merchant: String, amount: Int, amountEntered: Bool) -> Bool {
        !merchant.isEmpty && (amount > 0 || (amount == 0 && amountEntered))
    }

    static func canSaveReview(_ entry: ParsedEntry) -> Bool {
        canSaveReview(merchant: entry.merchant, amount: entry.amount, amountEntered: entry.amountEntered)
    }

    /// Validates history entry for editing (amount >= 0 allowed).
    static func canSaveEdit(merchant: String, amount: Int) -> Bool {
        !merchant.isEmpty && amount >= 0
    }
}
