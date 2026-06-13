import SwiftUI

extension ReconciliationVerdict.Tone {
    /// 정산 판정 톤 → 화면 색. 예산탭 행과 정산 화면이 같은 색을 쓰도록 단일 출처로 둔다.
    var color: Color {
        switch self {
        case .balanced: .green
        case .off: .orange
        case .inProgress: .secondary
        }
    }
}
