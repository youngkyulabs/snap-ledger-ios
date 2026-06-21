import Foundation
import SwiftData

/// CSV 저장 폴더 접근 공통 로직: settings 조회 → bookmark resolve →
/// security scope 시작 → 폴더 도달성 확인 → body 실행 → stale bookmark 갱신.
/// `SaveCoordinator`·`SyncCoordinator`가 공유한다. 실패는 중립 `AccessError`로 던지고
/// 각 호출자가 자신의 사용자 노출 에러 타입(`CoordinatorError`/`SyncError`)으로 매핑한다.
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

    /// resolve된 폴더 URL과 stale 갱신에 필요한 컨텍스트(settings·isStale)를 함께 묶는다.
    private struct ResolvedFolder {
        let url: URL
        let settings: AppSettings
        let isStale: Bool

        /// bookmark가 stale이면 새 bookmark를 만들어 저장한다.
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
