import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct AppSettingsOnboardingTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func hasCompletedOnboardingDefaultsToFalse() {
        let settings = AppSettings()
        #expect(settings.hasCompletedOnboarding == false)
    }

    @Test func hasCompletedOnboardingPersistsWhenSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let settings = AppSettings()
        context.insert(settings)
        settings.hasCompletedOnboarding = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>()).first
        #expect(fetched?.hasCompletedOnboarding == true)
    }

    @Test func hasMigratedToCloudStoreDefaultsFalse() {
        let settings = AppSettings()
        #expect(settings.hasMigratedToCloudStore == false)
    }
}
