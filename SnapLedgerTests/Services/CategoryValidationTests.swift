import Testing
@testable import SnapLedger

/// `CategoryValidation.isOffPreset` — 카테고리가 presets 밖(목록에 없음)인지.
/// 검토·수정 화면 off-list 경고의 단일 기준이다.
struct CategoryValidationTests {
    private let presets = ["식비", "카페", "기타"]

    @Test func nilIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset(nil, presets: presets) == false)
    }

    @Test func emptyIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset("", presets: presets) == false)
    }

    @Test func whitespaceOnlyIsNotOffPreset() {
        // 미지정에 준하는 공백만 값은 경고하지 않는다.
        #expect(CategoryValidation.isOffPreset("   ", presets: presets) == false)
    }

    @Test func presetMemberIsNotOffPreset() {
        #expect(CategoryValidation.isOffPreset("식비", presets: presets) == false)
    }

    @Test func unknownValueIsOffPreset() {
        #expect(CategoryValidation.isOffPreset("용돈", presets: presets) == true)
    }
}
