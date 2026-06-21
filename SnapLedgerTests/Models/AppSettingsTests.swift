import Testing
import SwiftData
@testable import SnapLedger

@Suite struct AppSettingsTests {
    @Test func entriesMigrationFlagDefaultsFalse() {
        let settings = AppSettings()
        #expect(settings.hasMigratedEntriesToCloudStore == false)
    }

    @Test func phase3MigrationFlagsDefaultFalse() {
        let settings = AppSettings()
        #expect(settings.hasMigratedReconciliationToCloudStore == false)
        #expect(settings.hasMigratedMerchantsToCloudStore == false)
    }
}
