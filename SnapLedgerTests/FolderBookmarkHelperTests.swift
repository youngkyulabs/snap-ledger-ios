import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct FolderBookmarkHelperTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fbh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func applyStoresResolvableBookmark() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let settings = AppSettings()
        context.insert(settings)
        let tmp = try makeTempFolder()

        try FolderBookmarkHelper.apply(url: tmp, to: settings, context: context)

        let data = try #require(settings.csvFolderBookmark)
        let resolved = try BookmarkStore.resolve(data)
        #expect(resolved.url.lastPathComponent == tmp.lastPathComponent)
    }
}
