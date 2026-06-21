import Testing
import SwiftData
@testable import SnapLedger

@Suite struct AppSettingsTests {
    @Test func entriesMigrationFlagDefaultsFalse() {
        let settings = AppSettings()
        #expect(settings.hasMigratedEntriesToCloudStore == false)
    }
}
