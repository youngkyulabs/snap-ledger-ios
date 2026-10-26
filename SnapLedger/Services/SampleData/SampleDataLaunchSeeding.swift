#if DEBUG
import Foundation
import OSLog
import SwiftData

/// Seeds sample data at launch when the app runs with `-SeedSampleData` (screenshot capture).
@MainActor
enum SampleDataLaunchSeeding {
    static let argument = "-SeedSampleData"

    private static let logger = Logger(subsystem: "com.youngkyu.snapledger", category: "sample-data")

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Seeds and completes onboarding; returns false when the iCloud gate blocks seeding or seeding fails.
    static func run(in context: ModelContext) async -> Bool {
        guard await SampleDataSeedGate.canSeedWithoutICloudPollution() else {
            logger.error("Sample seeding blocked: sign the simulator out of iCloud.")
            return false
        }
        do {
            try SampleDataSeeder().seed(into: context)
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? {
                let created = AppSettings()
                context.insert(created)
                return created
            }()
            settings.hasCompletedOnboarding = true
            try context.save()
            return true
        } catch {
            logger.error("Sample seeding failed: \(error.localizedDescription)")
            return false
        }
    }
}
#endif
