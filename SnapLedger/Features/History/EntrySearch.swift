import Foundation

/// 최근 기록 검색 필터. 설명(가맹점)·카테고리·메모 텍스트에 대해 대소문자를
/// 무시하고 부분 일치를 보고, 순수 숫자 쿼리는 금액과 정확히 일치할 때만 걸린다.
/// 공백만 있거나 빈 쿼리는 전체를 통과시킨다.
/// 순수 함수라 뷰(무한 스크롤·그룹핑)와 분리해 단위 테스트한다 (HistoryGrouping 옆).
enum EntrySearch {
    /// 금액 쿼리에서 무시하는 구분자 — 천 단위 콤마·공백·원/₩ 기호.
    private static let amountSeparators = CharacterSet(charactersIn: ", \t\n원₩")

    static func matches(_ entry: SavedEntry, query: String) -> Bool {
        matches(entry, trimmedQuery: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 이미 trim된 쿼리로 비교 — `filter`가 항목마다 쿼리를 다시 trim하지 않도록 내부 경로를 분리.
    private static func matches(_ entry: SavedEntry, trimmedQuery: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        if entry.merchant.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if let category = entry.category, category.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if let note = entry.note, note.localizedCaseInsensitiveContains(trimmedQuery) { return true }
        if amountMatches(entry, query: trimmedQuery) { return true }
        return false
    }

    /// 쿼리에서 콤마·공백·원/₩만 걷어내고, 남은 게 전부 ASCII 숫자일 때만 금액과
    /// 정확히 비교한다. `"12,000"`·`"12000원"`은 12000으로 매칭되지만, `"스벅 5000"`처럼
    /// 글자가 섞이면 숫자 쿼리가 아니라 매칭하지 않는다 (텍스트 검색만 적용).
    /// 부분일치가 아니라 정확일치라 `"1200"`·`"12300"`은 12000에 걸리지 않는다.
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
