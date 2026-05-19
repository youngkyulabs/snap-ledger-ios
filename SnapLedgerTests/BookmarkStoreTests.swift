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
}
