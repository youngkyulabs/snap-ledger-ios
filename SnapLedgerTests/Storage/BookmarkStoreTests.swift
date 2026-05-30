import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct BookmarkStoreTests {
    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    @Test func roundTripBookmark() throws {
        let tmp = try makeTempFolder()
        let data = try BookmarkStore.makeBookmark(for: tmp)
        #expect(!data.isEmpty)

        let resolved = try BookmarkStore.resolve(data)
        #expect(canonicalPath(resolved.url) == canonicalPath(tmp))
    }

    @Test func bookmarkSurvivesStorageRoundTrip() throws {
        let tmp = try makeTempFolder()
        let data = try BookmarkStore.makeBookmark(for: tmp)

        // Simulate persistence: encode -> decode via Data identity (the same bytes
        // are what's written to SwiftData's csvFolderBookmark field).
        let stored = Data(data)
        let resolved = try BookmarkStore.resolve(stored)
        #expect(canonicalPath(resolved.url) == canonicalPath(tmp))
    }

    @Test func resolveOfBogusDataThrows() {
        let bogus = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        #expect(throws: (any Error).self) {
            _ = try BookmarkStore.resolve(bogus)
        }
    }

    @Test func detectsTrashPathComponent() {
        let trashed = URL(fileURLWithPath:
            "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/.Trash/MyFolder")
        #expect(BookmarkStore.isInTrash(trashed))

        let normal = URL(fileURLWithPath:
            "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/MyFolder")
        #expect(!BookmarkStore.isInTrash(normal))
    }

    @Test func reachableDirectoryRejectsTrashedFolder() throws {
        // 실제로 존재하는 디렉토리지만 .Trash 안에 있으면 사용 가능한 폴더로 보지 않는다.
        let trashed = try makeTempFolder()
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent("MyFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)

        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(BookmarkStore.isInTrash(trashed))
        #expect(!BookmarkStore.isReachableDirectory(trashed))
    }
}
