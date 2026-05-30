import Foundation
import SwiftData

@MainActor
struct SaveCoordinator {
    let categoryLearner: CategoryLearner
    private let sync = SyncCoordinator()

    enum CoordinatorError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case externalConflict(months: [String])
        case fileNotReady(months: [String])

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 골라주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            case .externalConflict(let months):
                "\(months.joined(separator: ", ")) 파일이 앱 밖에서 변경됐어요. 먼저 가져오거나 덮어쓸지 선택해 주세요."
            case .fileNotReady(let months):
                "\(months.joined(separator: ", ")) 파일을 아직 받아오는 중이에요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    func save(
        _ entry: ParsedEntry,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw CoordinatorError.noCSVFolder
        }

        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try BookmarkStore.resolve(bookmark)
        } catch {
            throw CoordinatorError.bookmarkResolveFailed(underlying: error)
        }
        let folderURL = resolved.url

        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        let monthKey = CSVWriter.monthKey(for: entry.date)
        if !ignoringConflict {
            try ensureNoConflict(monthKeys: [monthKey], folderURL: folderURL, in: context)
        }

        let row = SavedRow(
            date: entry.date,
            description: entry.merchant,
            category: entry.category,
            amount: entry.amount,
            note: entry.note
        )
        let writer = CSVWriter(folder: folderURL)
        try writer.append(row)

        let saved = SavedEntry(
            date: entry.date,
            amount: entry.amount,
            merchant: entry.merchant,
            category: entry.category,
            note: entry.note,
            csvFile: Self.csvFilename(for: entry.date)
        )
        context.insert(saved)

        if let category = entry.category, !category.isEmpty {
            try categoryLearner.learn(
                merchant: entry.merchant, category: category, in: context
            )
        }

        entry.status = .dismissed
        sync.refreshFileState(monthKey: monthKey, folderURL: folderURL, in: context)
        try context.save()

        refreshStaleBookmark(resolved, settings: settings, folderURL: folderURL, in: context)
    }

    func update(
        _ entry: SavedEntry,
        originalDate: Date,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw CoordinatorError.noCSVFolder
        }

        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try BookmarkStore.resolve(bookmark)
        } catch {
            throw CoordinatorError.bookmarkResolveFailed(underlying: error)
        }
        let folderURL = resolved.url

        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        let newKey = CSVWriter.monthKey(for: entry.date)
        let oldKey = CSVWriter.monthKey(for: originalDate)
        let affectedKeys = Array(Set([oldKey, newKey]))

        if !ignoringConflict {
            try ensureNoConflict(monthKeys: affectedKeys, folderURL: folderURL, in: context)
        }

        entry.csvFile = CSVWriter.filename(forMonthKey: newKey)
        try context.save()

        try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)

        if let category = entry.category, !category.isEmpty {
            try categoryLearner.learn(
                merchant: entry.merchant, category: category, in: context
            )
        }
        try context.save()

        refreshStaleBookmark(resolved, settings: settings, folderURL: folderURL, in: context)
    }

    func delete(
        _ entry: SavedEntry,
        originalDate: Date? = nil,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw CoordinatorError.noCSVFolder
        }

        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try BookmarkStore.resolve(bookmark)
        } catch {
            throw CoordinatorError.bookmarkResolveFailed(underlying: error)
        }
        let folderURL = resolved.url

        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        let currentKey = CSVWriter.monthKey(for: entry.date)
        let oldKey = CSVWriter.monthKey(for: originalDate ?? entry.date)
        let affectedKeys = Array(Set([oldKey, currentKey]))

        if !ignoringConflict {
            try ensureNoConflict(monthKeys: affectedKeys, folderURL: folderURL, in: context)
        }

        context.delete(entry)
        try context.save()

        try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)
        try context.save()

        refreshStaleBookmark(resolved, settings: settings, folderURL: folderURL, in: context)
    }

    private func ensureNoConflict(
        monthKeys: [String],
        folderURL: URL,
        in context: ModelContext
    ) throws {
        switch sync.checkWriteGuard(monthKeys: monthKeys, folderURL: folderURL, in: context) {
        case .clear:
            return
        case .notReady(let keys):
            throw CoordinatorError.fileNotReady(months: keys)
        case .conflict(let keys):
            throw CoordinatorError.externalConflict(months: keys)
        }
    }

    private func refreshStaleBookmark(
        _ resolved: (url: URL, isStale: Bool),
        settings: AppSettings,
        folderURL: URL,
        in context: ModelContext
    ) {
        if resolved.isStale,
           let refreshed = try? BookmarkStore.makeBookmark(for: folderURL) {
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
    }

    private func fetchOrCreateSettings(in context: ModelContext) throws -> AppSettings {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let first = existing.first { return first }
        let new = AppSettings()
        context.insert(new)
        try context.save()
        return new
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static func csvFilename(for date: Date) -> String {
        "expenses-\(monthFormatter.string(from: date)).csv"
    }
}
