import Foundation

extension FoundationModelsExtractionService {
    /// Clears the whole breakdown when any item copies a placeholder, since a partial one no longer adds up to the total.
    static func droppingExampleItems(_ trans: PaymentTransaction) -> PaymentTransaction {
        let leaked = trans.items.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(exampleItemPrefix)
        }
        guard leaked else { return trans }
        var t = trans
        t.items = []
        return t
    }

    /// Labels of notification lines that report bookkeeping amounts rather than purchases.
    private static let nonSpendingItemLabels = ["인센티브", "잔액", "누적", "적립", "포인트", "캐시백", "마일리지", "한도"]

    /// Drops items named after a bookkeeping line (incentive, balance, points) when the payment stands without
    /// them: nothing else is listed and none of them is the payment itself, or the other items add up to it.
    static func droppingNonSpendingItems(_ trans: PaymentTransaction) -> PaymentTransaction {
        guard trans.amount > 0 else { return trans }
        func isLabelled(_ item: PaymentLineItem) -> Bool {
            nonSpendingItemLabels.contains { item.name.contains($0) }
        }
        let rest = trans.items.filter { !isLabelled($0) }
        guard rest.count < trans.items.count else { return trans }
        let standsWithout = rest.isEmpty
            ? !trans.items.contains { $0.amount == trans.amount }
            : rest.reduce(0) { $0 + $1.amount } == trans.amount
        guard standsWithout else { return trans }
        var t = trans
        t.items = rest
        return t
    }

    /// Words a notification uses for the payment's status; an item named only with them is not a purchase.
    private static let paymentStatusWords = ["일시불", "결제", "완료", "승인", "할부"]

    private static func isStatusLabel(_ name: String) -> Bool {
        let compact = name.filter { !$0.isWhitespace }
        return !compact.isEmpty
            && paymentStatusWords.reduce(compact) { $0.replacingOccurrences(of: $1, with: "") }.isEmpty
    }

    /// Whether a lone item's name is a status label or holds a word the source text does not, so the model made it up.
    static func isMadeUpItemName(_ name: String, sourceText: String?) -> Bool {
        if isStatusLabel(name) { return true }
        guard let sourceText else { return false }
        let source = sourceText.lowercased().filter { !$0.isWhitespace }
        let lowered = name.lowercased()
        if source.contains(lowered.filter { !$0.isWhitespace }) { return false }
        return lowered.split(whereSeparator: \.isWhitespace).contains { !source.contains($0) }
    }

    /// Folds a lone item that only restates the payment: it names a merchant-less transaction, and is dropped
    /// when it repeats the merchant or repeats the amount under a made-up name. Any other distinct name is kept,
    /// since it may be the real merchant.
    static func foldingRestatedItem(_ trans: PaymentTransaction, sourceText: String? = nil) -> PaymentTransaction {
        guard trans.items.count == 1, let item = trans.items.first else { return trans }
        let merchant = trans.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var t = trans
        if merchant.isEmpty || isCardIssuerName(merchant) {
            guard item.amount == trans.amount else { return trans }
            if !isStatusLabel(name) { t.merchant = name }
        } else if !(name.isEmpty || namesOverlap(merchant, name)) {
            guard item.amount == trans.amount, isMadeUpItemName(name, sourceText: sourceText) else { return trans }
        }
        // The item's amount is what the entry saved before folding.
        t.amount = item.amount
        t.items = []
        return t
    }

    /// Whether the names match ignoring case and spacing, or one is the other followed by more words such as a branch name.
    private static func namesOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.lowercased().split(whereSeparator: \.isWhitespace)
        let b = rhs.lowercased().split(whereSeparator: \.isWhitespace)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.joined(separator: "") == b.joined(separator: "") { return true }
        return a.count < b.count ? b.starts(with: a) : a.starts(with: b)
    }

    /// Drops bare rows (no merchant, no items) that repeat a named transaction's amount on its date or with no
    /// date of their own, such as a receipt's card approval line read as a second payment, and empty rows beside
    /// transactions that carry data.
    static func droppingRedundantTransactions(_ transactions: [PaymentTransaction]) -> [PaymentTransaction] {
        func isNamed(_ t: PaymentTransaction) -> Bool {
            !t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasData = transactions.contains { isNamed($0) || $0.amount != 0 || !$0.items.isEmpty }
        return transactions.filter { t in
            guard !isNamed(t), t.items.isEmpty else { return true }
            if t.amount == 0 { return !hasData }
            let undated = t.date.trimmingCharacters(in: .whitespaces).isEmpty
            return !transactions.contains { isNamed($0) && $0.amount == t.amount && (undated || $0.date == t.date) }
        }
    }
}
