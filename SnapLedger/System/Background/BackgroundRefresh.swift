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
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        await processingTask.value
        task.setTaskCompleted(success: true)
    }
}
