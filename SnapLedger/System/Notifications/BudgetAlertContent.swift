import Foundation

/// 지출 저장 직후 그 카테고리가 예산 임계점(near/over)에 닿았을 때 보내는 로컬 알림 콘텐츠.
/// 토스트 UI를 대체한다 — foreground 표시는 NotificationPresenter가 배너로 처리한다.
enum BudgetAlertContent {
    /// foreground에서 이 카테고리의 알림만 배너로 띄우기 위한 식별자(NotificationPresenter가 검사).
    static let categoryIdentifier = "com.youngkyu.snapledger.budget-alert"

    /// 카테고리별로 식별자를 달리해, 같은 카테고리를 연속 저장하면 알림이 쌓이지 않고 교체된다.
    static func identifier(for category: String) -> String {
        "\(categoryIdentifier).\(category)"
    }

    static func title(for state: BudgetProgress.State) -> String {
        switch state {
        case .over: return "예산 초과"
        case .near: return "예산 임박"
        case .under: return "예산 진행"
        }
    }
}
