import Foundation

/// Validation helper for expense entries.
enum EntrySaveValidation {
    /// Validates review entry for saving (amount > 0 required).
    static func canSaveReview(merchant: String, amount: Int) -> Bool {
        !merchant.isEmpty && amount > 0
    }

    /// Validates history entry for editing (amount >= 0 allowed).
    static func canSaveEdit(merchant: String, amount: Int) -> Bool {
        !merchant.isEmpty && amount >= 0
    }
}
