import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct FileFingerprintTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func readsLocalFileContentAndHash() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("a.csv")
        let body = "날짜,설명\n2026-05-01,A\n"
        try Data(body.utf8).write(to: url, options: .atomic)

        guard case .ready(let content) = FileFingerprint.read(at: url) else {
            Issue.record("expected .ready")
            return
        }
        #expect(content.text == body)
        #expect(content.hash == FileFingerprint.sha256Hex(Data(body.utf8)))
    }

    @Test func missingFileReturnsMissing() {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("nope.csv")
        #expect(FileFingerprint.read(at: url) == .missing)
    }

    @Test func hashIsDeterministicAndContentSensitive() {
        let hashA = FileFingerprint.sha256Hex(Data("a".utf8))
        let hashA2 = FileFingerprint.sha256Hex(Data("a".utf8))
        let hashB = FileFingerprint.sha256Hex(Data("b".utf8))
        #expect(hashA == hashA2)
        #expect(hashA != hashB)
        #expect(hashA.count == 64)
    }
}
