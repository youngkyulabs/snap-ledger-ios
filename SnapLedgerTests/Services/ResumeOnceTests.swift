import Foundation
import Testing
@testable import SnapLedger

struct ResumeOnceTests {
    @Test func secondResumeIsIgnored() async throws {
        let value: String = try await withCheckedThrowingContinuation { cont in
            let once = ResumeOnce(cont)
            once.resume(returning: "first")
            once.resume(returning: "second")
            once.resume(throwing: OCRError.invalidImage)
        }
        #expect(value == "first")
    }

    @Test func firstThrowWins() async {
        var caught: (any Error)?
        do {
            let _: String = try await withCheckedThrowingContinuation { cont in
                let once = ResumeOnce(cont)
                once.resume(throwing: OCRError.invalidImage)
                once.resume(returning: "late")
            }
        } catch {
            caught = error
        }
        #expect(caught is OCRError)
    }
}
