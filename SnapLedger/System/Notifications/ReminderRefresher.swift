import Foundation
import SwiftData

/// 현재 설정·pending 카운트로 검토 알림을 재예약(또는 해제)하는 공용 진입점.
/// 알림은 1회성 예약이므로, 앱이 실행되는 모든 시점(포그라운드 진입·백그라운드
/// 전환·BGTask)에서 호출해 다음 발사를 재장전해야 한다.
@MainActor
enum ReminderRefresher {
    static func refresh(in context: ModelContext) async {
        let scheduler = NotificationScheduler()
        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first,
              settings.reminderEnabled else {
            scheduler.clear()
            return
        }
        let pendingCount = ((try? context.fetch(FetchDescriptor<ParsedEntry>())) ?? [])
            .filter { $0.status == .pending }
            .count
        await scheduler.refresh(
            hour: settings.reminderHour,
            minute: settings.reminderMinute,
            pendingCount: pendingCount
        )
    }
}
