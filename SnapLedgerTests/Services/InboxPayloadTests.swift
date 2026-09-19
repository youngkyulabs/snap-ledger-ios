import Foundation
import Testing
@testable import SnapLedger

@Suite
struct InboxPayloadTests {
    @Test func txtFilenameIsText() {
        #expect(InboxPayload.isText(filename: "\(UUID().uuidString).txt"))
    }

    @Test func uppercaseExtensionIsText() {
        #expect(InboxPayload.isText(filename: "shared.TXT"))
    }

    @Test func imageFilenameIsNotText() {
        #expect(InboxPayload.isText(filename: "receipt.jpg") == false)
        #expect(InboxPayload.isText(filename: "receipt.png") == false)
        #expect(InboxPayload.isText(filename: "noextension") == false)
    }

    @Test func readsUTF8Contents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).txt")
        try "신한카드 5,000원 일시불 스타벅스".write(to: url, atomically: true, encoding: .utf8)

        #expect(try InboxPayload.readText(at: url) == "신한카드 5,000원 일시불 스타벅스")
    }

    @Test func shortTextIsNotClamped() {
        let text = "신한카드 5,000원 일시불 스타벅스"

        #expect(InboxPayload.clampForExtraction(text) == text)
    }

    @Test func longTextIsClampedToExtractionLimit() {
        let limit = InboxPayload.extractionCharacterLimit
        let text = String(repeating: "가", count: limit + 500)

        let clamped = InboxPayload.clampForExtraction(text)

        #expect(clamped.count == limit)
        #expect(text.hasPrefix(clamped))
    }

    @Test func readingMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).txt")

        #expect(throws: (any Error).self) {
            try InboxPayload.readText(at: url)
        }
    }
}
