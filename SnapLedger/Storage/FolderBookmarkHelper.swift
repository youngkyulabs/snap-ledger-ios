import Foundation
import SwiftData

@MainActor
enum FolderBookmarkHelper {
    static func apply(url: URL, to settings: AppSettings, context: ModelContext) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try BookmarkStore.makeBookmark(for: url)
        settings.csvFolderBookmark = bookmark
        try context.save()
    }
}
