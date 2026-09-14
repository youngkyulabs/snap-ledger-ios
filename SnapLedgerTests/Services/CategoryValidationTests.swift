import Testing
@testable import SnapLedger

/// Verifies off-preset category detection.
struct CategoryValidationTests {
    private let presets = ["식비", "카페", "기타"]

    @Test func nilIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset(nil, presets: presets) == false)
    }

    @Test func emptyIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset("", presets: presets) == false)
    }

    @Test func whitespaceOnlyIsNotOffPreset() {
        // Empty/whitespace categories do not trigger off-preset warning.
        #expect(CategoryValidation.isOffPreset("   ", presets: presets) == false)
    }

    @Test func presetMemberIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset("식비", presets: presets) == false)
    }

    @Test func unknownValueIsOffPreset() {
        #expect(CategoryValidation.isOffPreset("용돈", presets: presets) == true)
    }
}
