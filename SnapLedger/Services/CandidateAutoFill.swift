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
}
