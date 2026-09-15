import SwiftData
import Testing
@testable import SnapLedger

struct CategoryPresetTests {
    /// Verifies zero-argument initializer requirement for CloudKit.
    @Test func defaultInitializerHasDefaults() {
        let preset = CategoryPreset()
        #expect(preset.name.isEmpty)
        #expect(preset.sortOrder == 0)
    }

    @Test func storesNameAndOrder() {
        let preset = CategoryPreset(name: "식비", sortOrder: 3)
        #expect(preset.name == "식비")
        #expect(preset.sortOrder == 3)
    }
}
