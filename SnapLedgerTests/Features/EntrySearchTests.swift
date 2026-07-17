import Foundation
import Testing
@testable import SnapLedger

/// `EntrySearch` — 최근 기록 검색. 설명·카테고리·메모 대소문자 무시 부분 일치 + 금액 정확일치.
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

    // MARK: - 금액 검색 (정확일치)

    @Test func matchesExactAmount() {
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12000") == true)
    }

    @Test func stripsThousandsSeparatorAndWon() {
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12,000") == true)
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12000원") == true)
        #expect(EntrySearch.matches(entry(amount: 12_000), query: "12,000 원") == true)
    }

    @Test func partialDigitsDoNotMatchAmount() {
        // 정확일치라 접두(1200)·유사(12300) 숫자는 12000에 걸리지 않는다.
        #expect(EntrySearch.matches(entry(merchant: "마트", category: nil, amount: 12_000), query: "1200") == false)
        #expect(EntrySearch.matches(entry(merchant: "마트", category: nil, amount: 12_000), query: "12300") == false)
    }

    @Test func mixedQueryDoesNotMatchAmount() {
        // 글자가 섞인 쿼리는 숫자 쿼리가 아니므로 금액 매칭 안 함 (텍스트 검색만).
        let subject = entry(merchant: "스타벅스", category: nil, note: nil, amount: 5000)
        #expect(EntrySearch.matches(subject, query: "스벅 5000") == false)
    }

    @Test func amountQueryStillMatchesMerchantContainingDigits() {
        // 숫자 쿼리라도 가맹점 텍스트에 그 숫자가 있으면 텍스트 경로로 걸린다.
        #expect(EntrySearch.matches(entry(merchant: "GS25", category: nil, amount: 9900), query: "25") == true)
    }
}
