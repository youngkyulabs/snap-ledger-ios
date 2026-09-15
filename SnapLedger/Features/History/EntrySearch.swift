import Foundation

/// Search filter matching text fields partially or amounts exactly.
enum EntrySearch {
    /// Punctuation and currency symbols ignored in amount queries.
    private static let amountSeparators = CharacterSet(charactersIn: ", \t\n원₩")

    static func matches(_ entry: SavedEntry, query: String) -> Bool {
        matches(entry, trimmedQuery: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Compares entry fields against a pre-trimmed query string.
    private static func matches(_ entry: SavedEntry, trimmedQuery: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        if entry.merchant.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if let category = entry.category, category.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if let note = entry.note, note.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if amountMatches(entry, query: trimmedQuery) { return true }
        return false
    }

    /// Parses query as exact amount when stripped of punctuation.
    static func amountMatches(_ entry: SavedEntry, query: String) -> Bool {
        let stripped = query.components(separatedBy: amountSeparators).joined()
        guard !stripped.isEmpty,
              stripped.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(stripped) else { return false }
        return value == entry.amount
    }

    static func filter(_ entries: [SavedEntry], query: String) -> [SavedEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { matches($0, trimmedQuery: trimmed) }
    }
}
