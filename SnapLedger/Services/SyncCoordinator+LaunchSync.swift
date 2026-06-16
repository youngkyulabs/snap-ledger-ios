import Foundation
import SwiftData

extension SyncCoordinator {
    /// 앱 진입 시 외부 변경 처리 결과.
    enum LaunchSyncOutcome: Equatable {
        /// 자동 동기화 꺼짐 — 사용자에게 알릴 변경 목록.
        case detected([DetectedChange])
        /// 자동 동기화 켜짐 — 파일→앱 자동 가져오기 결과.
        case applied(ImportSummary)
    }

    /// 앱 진입 시 한 번 호출. baseline을 보정하고 외부 변경을 감지한 뒤,
    /// 자동 동기화가 켜져 있으면 종류별로 파일→앱 가져오기를 수행한다.
    func resolveExternalChangesOnLaunch(
        autoApply: Bool,
        in context: ModelContext
    ) async -> LaunchSyncOutcome {
        establishBaselineIfNeeded(in: context)
        let changes = await detectChanges(in: context)
        guard autoApply else { return .detected(changes) }
        var summary = ImportSummary()
        let byKind = Dictionary(grouping: changes, by: \.fileKind)
        for (kind, kindChanges) in byKind {
            let keys = kindChanges.map(\.monthKey)
            if let kindSummary = try? importMonths(keys, kind: kind, in: context) {
                summary.merge(kindSummary)
            }
        }
        return .applied(summary)
    }
}
