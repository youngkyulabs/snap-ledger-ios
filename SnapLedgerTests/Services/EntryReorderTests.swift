import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct EntryReorderTests {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @Test func sortsDistinctValuesDescending() {
        let out = EntryReorder.descendingTimestamps(from: [date(100), date(300), date(200)])
        #expect(out == [date(300), date(200), date(100)])
    }

    @Test func emptyAndSingleArePassedThrough() {
        #expect(EntryReorder.descendingTimestamps(from: []).isEmpty)
        #expect(EntryReorder.descendingTimestamps(from: [date(5)]) == [date(5)])
    }

    @Test func duplicatesBecomeStrictlyDescending() {
        let out = EntryReorder.descendingTimestamps(from: [date(100), date(100), date(100)])
        #expect(out.count == 3)
        // 최댓값은 그대로 두고, 중복은 아래로 밀어 항상 순서가 결정되게 한다.
        #expect(out[0] == date(100))
        for index in 1..<out.count {
            #expect(out[index] < out[index - 1])
        }
    }

    @Test func mixedDuplicatesKeepDistinctValuesInPlace() {
        let out = EntryReorder.descendingTimestamps(from: [date(200), date(100), date(200)])
        #expect(out.count == 3)
        #expect(out[0] == date(200))
        for index in 1..<out.count {
            #expect(out[index] < out[index - 1])
        }
        // 중복 보정이 멀리 떨어진 기존 값까지 끌어내리지는 않는다.
        #expect(out[2] == date(100))
    }
}
