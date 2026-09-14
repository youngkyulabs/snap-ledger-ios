import Foundation
import SwiftData

/// One-way exporter from SwiftData to monthly CSV files.
@MainActor
struct SyncCoordinator {
    enum SyncError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case folderUnavailable

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 선택해 주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            case .folderUnavailable:
                "저장 폴더를 찾을 수 없어요. 폴더가 삭제됐거나 이동했을 수 있어요. 설정 → 저장 폴더에서 다시 선택해 주세요."
            }
        }
    }

    /// Checks whether storage folder bookmark is reachable.
    func isFolderReachable(in context: ModelContext) -> Bool? {
        guard let settings = try? CSVFolderAccess.fetchOrCreateSettings(in: context),
              let bookmark = settings.csvFolderBookmark else {
            return nil
        }
        guard let resolved = try? BookmarkStore.resolve(bookmark) else {
            return false
        }
        let url = resolved.url
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return BookmarkStore.isReachableDirectory(url)
    }

    // MARK: - Export (App -> Files, One-way)

    /// Backfills all months to CSV files in the storage folder.
    func exportAll(in context: ModelContext) throws {
        let savedKeys = Set(
            ((try? context.fetch(FetchDescriptor<SavedEntry>())) ?? [])
                .map { CSVWriter.monthKey(for: $0.date) }
        )
        let reconciliationKeys = reconciliationMonthKeys(in: context)
        let budgetKeys = budgetMonthKeys(in: context)
        try withFolder(in: context) { folderURL, ctx in
            try exportMonths(Array(savedKeys), folderURL: folderURL, in: ctx)
            try exportReconciliationMonths(Array(reconciliationKeys), folderURL: folderURL, in: ctx)
            try exportBudgetMonths(Array(budgetKeys), folderURL: folderURL, in: ctx)
            try ctx.save()
        }
    }

    /// Rewrites expense CSV files for specified months.
    func exportMonths(_ keys: [String], folderURL: URL, in context: ModelContext) throws {
        let writer = CSVWriter(folder: folderURL)
        let allSaved = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
        for key in keys {
            let rows = allSaved
                .filter { CSVWriter.monthKey(for: $0.date) == key }
                .sorted { $0.savedAt < $1.savedAt }
                .map {
                    SavedRow(
                        date: $0.date,
                        description: $0.merchant,
                        category: $0.category,
                        amount: $0.amount,
                        note: $0.note
                    )
                }
            try writer.replaceMonth(monthKey: key, rows: rows)
        }
    }

    // MARK: - Folder Access

    /// Provides scoped access to the configured storage folder.
    private func withFolder<T>(
        in context: ModelContext,
        _ body: (URL, ModelContext) throws -> T
    ) throws -> T {
        do {
            return try CSVFolderAccess.withFolder(in: context) { folderURL in
                try body(folderURL, context)
            }
        } catch let error as CSVFolderAccess.AccessError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: CSVFolderAccess.AccessError) -> SyncError {
        switch error {
        case .noCSVFolder: .noCSVFolder
        case .bookmarkResolveFailed(let underlying): .bookmarkResolveFailed(underlying: underlying)
        case .folderUnavailable: .folderUnavailable
        }
    }
}
