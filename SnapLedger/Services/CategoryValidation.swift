import Foundation

/// 카테고리 값이 사용자 presets(추천 목록) 밖인지 판정한다. 검토·수정 화면에서
/// off-list 경고를 띄울지 결정하는 단일 기준 — 수동 입력·추출·학습·외부 import가
/// 모두 같은 규칙을 따른다. 빈 값/공백/미지정은 경고 대상이 아니다.
enum CategoryValidation {
    static func isOffPreset(_ category: String?, presets: [String]) -> Bool {
        guard let category,
              !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return !presets.contains(category)
    }
}
