import Foundation

/// 추출 결과의 빈 칸을 후보로 자동 채운다 (검토 항목 생성 시). 사용자 검토 부담을 줄이되,
/// 모호한 경우(금액 후보가 여러 개)는 채우지 않아 0원 가드가 미검토 항목을 계속 걸러내도록 한다.
enum CandidateAutoFill {
    /// 설명(가맹점): 비어 있으면 첫 후보로, 아니면 그대로.
    static func merchant(current: String, candidates: [String]) -> String {
        current.isEmpty ? (candidates.first ?? current) : current
    }

    /// 금액: 0이고 후보가 정확히 1개(모호하지 않음)일 때만 그 후보로, 아니면 그대로.
    static func amount(current: Int, candidates: [Int]) -> Int {
        current == 0 && candidates.count == 1 ? candidates[0] : current
    }

    /// 카테고리: 학습값이 **현재 presets 안일 때만** 우선 적용하고, 프리셋 밖(off-list)
    /// 이거나 비어 있으면 버리고 추출값으로 폴백한다. 둘 다 없으면 nil(사용자가 직접 선택).
    ///
    /// 학습값이 추출값을 무조건 이기던 기존 동작은, 사용자가 프리셋에서 지운/바꾼 옛
    /// 카테고리를 검토 자동채움에 계속 되살리는 문제가 있었다. off-list 판정은
    /// `CategoryValidation`(경고 기준)과 같은 단일 규칙을 재사용한다.
    static func category(learned: String?, extracted: String?, presets: [String]) -> String? {
        if let learned,
           !learned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !CategoryValidation.isOffPreset(learned, presets: presets) {
            return learned
        }
        return extracted
    }
}
