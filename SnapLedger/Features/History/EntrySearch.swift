import Foundation

/// 최근 기록 검색 필터. 설명(가맹점)·카테고리·메모 텍스트에 대해 대소문자를
/// 무시하고 부분 일치를 본다. 공백만 있거나 빈 쿼리는 전체를 통과시킨다.
/// 순수 함수라 뷰(무한 스크롤·그룹핑)와 분리해 단위 테스트한다 (HistoryGrouping 옆).
enum EntrySearch {
    static func matches(_ entry: SavedEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if entry.merchant.localizedCaseInsensitiveContains(trimmed) { return true }
        if let category = entry.category, category.localizedCaseInsensitiveContains(trimmed) { return true }
        if let note = entry.note, note.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }

    static func filter(_ entries: [SavedEntry], query: String) -> [SavedEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { matches($0, query: trimmed) }
    }
}
