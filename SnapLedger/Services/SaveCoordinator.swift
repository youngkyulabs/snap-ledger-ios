import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "save")

/// DTO holding edited fields for a saved entry.
struct SavedEntryEdit: Equatable {
    var date: Date
    var merchant: String
    var amount: Int
    var category: String?
    var note: String?
}

@MainActor
struct SaveCoordinator {
    let categoryLearner: CategoryLearner
    private let sync = SyncCoordinator()

    func save(
        _ entry: ParsedEntry,
        in context: ModelContext
    ) throws {
        let monthKey = CSVWriter.monthKey(for: entry.date)
        // Insert new saved entry and dismiss review item
        context.insert(
            SavedEntry(
                date: entry.date,
                amount: entry.amount,
                merchant: entry.merchant,
                category: entry.category,
                note: entry.note,
                csvFile: CSVWriter.filename(forMonthKey: monthKey)
            )
        )
        entry.status = .dismissed
        try context.save()

        exportEntryBestEffort(monthKeys: [monthKey], in: context)
        learnCategoryBestEffort(merchant: entry.merchant, category: entry.category, in: context)
    }

    /// Updates existing saved entry with edited fields.
    func update(
        _ entry: SavedEntry,
        to edit: SavedEntryEdit,
        in context: ModelContext
    ) throws {
        // Month keys affected by date change
        let oldKey = CSVWriter.monthKey(for: entry.date)
        let newKey = CSVWriter.monthKey(for: edit.date)
        let affectedKeys = Array(Set([oldKey, newKey]))

        entry.date = edit.date
        entry.merchant = edit.merchant
        entry.amount = edit.amount
        entry.category = edit.category
        entry.note = edit.note
        entry.csvFile = CSVWriter.filename(forMonthKey: newKey)
        try context.save()

        exportEntryBestEffort(monthKeys: affectedKeys, in: context)
        learnCategoryBestEffort(merchant: entry.merchant, category: entry.category, in: context)
    }

    func delete(
        _ entry: SavedEntry,
        originalDate: Date? = nil,
        in context: ModelContext
    ) throws {
        let currentKey = CSVWriter.monthKey(for: entry.date)
        let oldKey = CSVWriter.monthKey(for: originalDate ?? entry.date)
        let affectedKeys = Array(Set([oldKey, currentKey]))

        context.delete(entry)
        try context.save()

        exportEntryBestEffort(monthKeys: affectedKeys, in: context)
    }

    /// Persists new display ordering among saved entries.
    func reorder(
        _ entries: [SavedEntry],
        in context: ModelContext
    ) throws {
        guard entries.count > 1 else { return }
        let monthKeys = Array(Set(entries.map { CSVWriter.monthKey(for: $0.date) }))
        let stamps = EntryReorder.descendingTimestamps(from: entries.map(\.savedAt))
        for (entry, stamp) in zip(entries, stamps) {
            entry.savedAt = stamp
        }
        try context.save()

        exportEntryBestEffort(monthKeys: monthKeys, in: context)
    }

    /// Rewrites CSV files for affected months best-effort.
    private func exportEntryBestEffort(monthKeys: [String], in context: ModelContext) {
        guard !monthKeys.isEmpty else { return }
        do {
            try CSVFolderAccess.withFolder(in: context) { folderURL in
                try sync.exportMonths(monthKeys, folderURL: folderURL, in: context)
                try sync.exportBudgetMonths(monthKeys, folderURL: folderURL, in: context)
            }
        } catch CSVFolderAccess.AccessError.noCSVFolder {
            // Skip silently if no folder is configured
        } catch {
            log.error("CSV export(best-effort) failed: \(String(describing: error))")
        }
    }

    /// Learns merchant to category mapping best-effort.
    private func learnCategoryBestEffort(
        merchant: String,
        category: String?,
        in context: ModelContext
    ) {
        guard let category, !category.isEmpty else { return }
        do {
            try categoryLearner.learn(merchant: merchant, category: category, in: context)
        } catch {
            log.error("category learn failed: \(String(describing: error))")
        }
    }
}
