import Foundation

/// 저장 가능 여부 판정. 검토 화면과 편집 화면의 0원 정책이 다르다.
enum EntrySaveValidation {
    /// 검토(추출 결과) 저장: 0원을 막는다. 추출이 금액을 못 뽑으면 `amount`가 기본값 0으로
    /// 남는 경우가 많아(가맹점/금액은 비고 후보 칩만 있는 상태), 미검토 항목이 0원으로 새어
    /// 저장되는 것을 방지한다. 사용자는 후보 칩 선택이나 직접 입력으로 금액을 채워야 저장된다.
    static func canSaveReview(merchant: String, amount: Int) -> Bool {
        !merchant.isEmpty && amount > 0
    }

    /// 편집(기록 수정) 저장: 0원을 허용한다(음수만 차단). 이미 저장된 항목을 사용자가
    /// 의도적으로 0원으로 고치거나, 0원 항목을 다시 저장하는 경우를 막지 않는다.
    static func canSaveEdit(merchant: String, amount: Int) -> Bool {
        !merchant.isEmpty && amount >= 0
    }
}
