import Foundation
import Testing
@testable import SnapLedger

/// EntrySearch tests: partial text match and exact amount match.
@MainActor
struct EntrySearchTests {
    private func entry(
        merchant: String = "스타벅스",
        category: String? = "카페",
        note: String? = nil,
        amount: Int = 4500
    ) -> SavedEntry {
        SavedEntry(
            date: .now,
            amount: amount,
            merchant: merchant,
            category: category,
            note: note,
            savedAt: .now,
            csvFile: "expenses-2026-07.csv"
        )
    }

    @Test func matchesMerchant() {
        #expect(EntrySearch.matches(entry(merchant: "스타벅스"), query: "스타") == true)
    }

    @Test func matchesCategory() {
        #expect(EntrySearch.matches(entry(category: "카페"), query: "카페") == true)
    }

    @Test func matchesNote() {
        #expect(EntrySearch.matches(entry(note: "회식 정산"), query: "정산") == true)
    }

    @Test func isCaseInsensitive() {
        #expect(EntrySearch.matches(entry(merchant: "Starbucks"), query: "starb") == true)
    }

    @Test func noMatchReturnsFalse() {
        let subject = entry(merchant: "스타벅스", category: "카페", note: "아침")
        #expect(EntrySearch.matches(subject, query: "택시") == false)
    }

    @Test func nilCategoryAndNoteDoNotMatch() {
        let subject = entry(merchant: "스타벅스", category: nil, note: nil)
        #expect(EntrySearch.matches(subject, query: "카페") == false)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(EntrySearch.matches(entry(), query: "") == true)
        #expect(EntrySearch.matches(entry(), query: "   ") == true)
    }

    @Test func filterKeepsOnlyMatches() {
        let entries = [
            entry(merchant: "스타벅스", category: "카페"),
            entry(merchant: "지하철", category: "교통"),
            entry(merchant: "투썸", category: "카페"),
        ]
        let out = EntrySearch.filter(entries, query: "카페")
        #expect(out.count == 2)
        #expect(out.allSatisfy { $0.category == "카페" })
    }

    @Test func filterWithEmptyQueryReturnsAll() {
        let entries = [entry(merchant: "A"), entry(merchant: "B")]
        #expect(EntrySearch.filter(entries, query: "  ").count == 2)
    }

    // MARK: - Amount Search (Exact Match)

    @Test func matchesExactAmount() {
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12000") == true)
    }

    @Test func stripsThousandsSeparatorAndWon() {
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12,000") == true)
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12000원") == true)
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12,000 원") == true)
    }

    @Test func partialDigitsDoNotMatchAmount() {
        // Exact match does not match prefix (1200) or similar (12300) numbers.
        #expect(EntrySearch.matches(entry(merchant: "마트", category: nil, amount: 12_000), query: "1200") == false)
        #expect(EntrySearch.matches(entry(merchant: "마트", category: nil, amount: 12_000), query: "12300") == false)
    }

    @Test func mixedQueryDoesNotMatchAmount() {
        // Mixed text is not treated as numeric query.
        let subject = entry(merchant: "스타벅스", category: nil, note: nil, amount: 5000)
        #expect(EntrySearch.matches(subject, query: "스벅 5000") == false)
    }

    @Test func amountQueryStillMatchesMerchantContainingDigits() {
        // Numeric query matches if merchant name contains the string.
        #expect(EntrySearch.matches(entry(merchant: "GS25", category: nil, amount: 9900), query: "25") == true)
    }
}
