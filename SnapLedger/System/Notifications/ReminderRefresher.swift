import Foundation
import SwiftData

/// Reschedules reminder notifications based on current settings and pending count.
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
