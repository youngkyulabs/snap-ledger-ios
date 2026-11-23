import Foundation

/// Maps the review amount field to a ParsedEntry, keeping a typed 0 apart from an empty field.
enum ReviewAmountInput {
    static func displayValue(for entry: ParsedEntry) -> Int? {
        entry.amount == 0 && !entry.amountEntered ? nil : entry.amount
    }

    static func apply(_ value: Int?, to entry: ParsedEntry) {
        entry.amount = value ?? 0
        entry.amountEntered = value != nil
    }
}
