import SwiftData
import Testing
@testable import SnapLedger

struct CategoryPresetTests {
    /// CloudKit 제약: 인자 없이 생성 가능(모든 속성 기본값)해야 한다.
    @Test func defaultInitializerHasDefaults() {
        let preset = CategoryPreset()
        #expect(preset.name == "")
        #expect(preset.sortOrder == 0)
    }

    @Test func storesNameAndOrder() {
        let preset = CategoryPreset(name: "식비", sortOrder: 3)
        #expect(preset.name == "식비")
        #expect(preset.sortOrder == 3)
    }
}
