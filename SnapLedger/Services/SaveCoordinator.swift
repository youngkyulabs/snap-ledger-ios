import Foundation
import SwiftData

@MainActor
struct SaveCoordinator {
    let categoryLearner: CategoryLearner

    enum CoordinatorError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 골라주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            }
        }
    }

    func save(_ entry: ParsedEntry, in context: ModelContext) throws {
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
        try context.save()

        if resolved.isStale,
           let refreshed = try? BookmarkStore.makeBookmark(for: folderURL) {
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
    }

    func update(
        _ entry: SavedEntry,
        originalDate: Date,
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
        entry.csvFile = CSVWriter.filename(forMonthKey: newKey)

        try context.save()

        let writer = CSVWriter(folder: folderURL)
        let affectedKeys: Set<String> = [oldKey, newKey]
        let allSaved = try context.fetch(FetchDescriptor<SavedEntry>())
        for key in affectedKeys {
            let rows = allSaved
                .filter { CSVWriter.monthKey(for: $0.date) == key }
                .sorted { $0.savedAt < $1.savedAt }
                .map { entry in
                    SavedRow(
                        date: entry.date,
                        description: entry.merchant,
                        category: entry.category,
                        amount: entry.amount,
                        note: entry.note
                    )
                }
            try writer.replaceMonth(monthKey: key, rows: rows)
        }

        if let category = entry.category, !category.isEmpty {
            try categoryLearner.learn(
                merchant: entry.merchant, category: category, in: context
            )
        }

        if resolved.isStale,
           let refreshed = try? BookmarkStore.makeBookmark(for: folderURL) {
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
    }

    func delete(
        _ entry: SavedEntry,
        originalDate: Date? = nil,
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
        context.delete(entry)
        try context.save()

        let writer = CSVWriter(folder: folderURL)
        let affectedKeys: Set<String> = [oldKey, currentKey]
        let allSaved = try context.fetch(FetchDescriptor<SavedEntry>())
        for key in affectedKeys {
            let rows = allSaved
                .filter { CSVWriter.monthKey(for: $0.date) == key }
                .sorted { $0.savedAt < $1.savedAt }
                .map { entry in
                    SavedRow(
                        date: entry.date,
                        description: entry.merchant,
                        category: entry.category,
                        amount: entry.amount,
                        note: entry.note
                    )
                }
            try writer.replaceMonth(monthKey: key, rows: rows)
        }

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
