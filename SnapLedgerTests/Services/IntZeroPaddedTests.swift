import Testing
@testable import SnapLedger

struct IntZeroPaddedTests {
    @Test(arguments: [
        (7, 2, "07"),
        (12, 2, "12"),
        (123, 2, "123"),
        (2026, 4, "2026"),
        (0, 4, "0000"),
        (-5, 3, "-05"),
        (-123, 2, "-123"),
    ])
    func matchesPrintfZeroPadding(value: Int, width: Int, expected: String) {
        #expect(value.zeroPadded(width) == expected)
    }
}
