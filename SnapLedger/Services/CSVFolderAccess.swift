import Foundation
import SwiftData

/// Helper for safely accessing security-scoped CSV storage folder.
@MainActor
enum CSVFolderAccess {
    enum AccessError: Error {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case folderUnavailable
    }

    static func fetchOrCreateSettings(in context: ModelContext) throws -> AppSettings {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let first = existing.first { return first }
        let new = AppSettings()
        context.insert(new)
        try context.save()
        return new
    }

    static func withFolder<T>(
        in context: ModelContext,
        _ body: (URL) throws -> T
    ) throws -> T {
        let resolved = try resolveFolder(in: context)
        let didStart = resolved.url.startAccessingSecurityScopedResource()
        defer { if didStart { resolved.url.stopAccessingSecurityScopedResource() } }
        try ensureReachable(resolved.url)
        let result = try body(resolved.url)
        resolved.refreshStaleBookmarkIfNeeded(in: context)
        return result
    }

    /// Validated folder URL and security-scope context.
    private struct ResolvedFolder {
        let url: URL
        let settings: AppSettings
        let isStale: Bool

        /// Renews and persists a stale security-scoped bookmark.
        func refreshStaleBookmarkIfNeeded(in context: ModelContext) {
            guard isStale, let refreshed = try? BookmarkStore.makeBookmark(for: url) else { return }
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
    }

    private static func resolveFolder(in context: ModelContext) throws -> ResolvedFolder {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw AccessError.noCSVFolder
        }
        do {
            let resolved = try BookmarkStore.resolve(bookmark)
            return ResolvedFolder(url: resolved.url, settings: settings, isStale: resolved.isStale)
        } catch {
            throw AccessError.bookmarkResolveFailed(underlying: error)
        }
    }

    private static func ensureReachable(_ folderURL: URL) throws {
        guard BookmarkStore.isReachableDirectory(folderURL) else {
            throw AccessError.folderUnavailable
        }
    }
}
