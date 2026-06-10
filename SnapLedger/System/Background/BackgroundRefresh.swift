import BackgroundTasks
import Foundation
import SwiftData

enum BackgroundRefresh {
    static let taskIdentifier = "com.youngkyu.snapledger.refresh"
    static let nextRunInterval: TimeInterval = 60 * 60 // 1시간

    @MainActor
    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: .main
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await handle(task: task, modelContainer: modelContainer)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: nextRunInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handle(task: BGAppRefreshTask, modelContainer: ModelContainer) async {
        schedule()

        let processingTask = Task { @MainActor in
            let context = ModelContext(modelContainer)
            await PendingProcessor.make(in: context).drain(in: context)

            let pendingCount = ((try? context.fetch(FetchDescriptor<ParsedEntry>())) ?? [])
                .filter { $0.status == .pending }
                .count
            await NotificationScheduler().syncIconBadge(count: pendingCount)
            // drain으로 pending 카운트가 바뀌었을 수 있고, 1회성 알림은 발사 후
            // 소비되므로 백그라운드 주기마다 최신 카운트로 재장전한다.
            await ReminderRefresher.refresh(in: context)
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        await processingTask.value
        task.setTaskCompleted(success: true)
    }
}
