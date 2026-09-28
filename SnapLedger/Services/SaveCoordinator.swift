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
        let saved = SavedEntry(
            date: entry.date,
            amount: entry.amount,
            merchant: entry.merchant,
            category: entry.category,
            note: entry.note,
            csvFile: CSVWriter.filename(forMonthKey: monthKey)
        )
        let previousStatus = entry.status
        // Insert new saved entry and dismiss review item
        context.insert(saved)
        entry.status = .dismissed
        try saveOrUndo(context) {
            context.delete(saved)
            entry.status = previousStatus
        }

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
        let previous = SavedEntryEdit(
            date: entry.date,
            merchant: entry.merchant,
            amount: entry.amount,
            category: entry.category,
            note: entry.note
        )
        let previousFile = entry.csvFile

        apply(edit, to: entry)
        entry.csvFile = CSVWriter.filename(forMonthKey: newKey)
        try saveOrUndo(context) {
            apply(previous, to: entry)
            entry.csvFile = previousFile
        }

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
        // SwiftData cannot unstage a single delete, so a failed delete rolls back the whole context.
        try saveOrUndo(context) { context.rollback() }

        exportEntryBestEffort(monthKeys: affectedKeys, in: context)
    }

    /// Persists new display ordering among saved entries.
    func reorder(
        _ entries: [SavedEntry],
        in context: ModelContext
    ) throws {
        guard entries.count > 1 else { return }
        let monthKeys = Array(Set(entries.map { CSVWriter.monthKey(for: $0.date) }))
        let previousStamps = entries.map(\.savedAt)
        let stamps = EntryReorder.descendingTimestamps(from: previousStamps)
        for (entry, stamp) in zip(entries, stamps) {
            entry.savedAt = stamp
        }
        try saveOrUndo(context) {
            for (entry, stamp) in zip(entries, previousStamps) {
                entry.savedAt = stamp
            }
        }

        exportEntryBestEffort(monthKeys: monthKeys, in: context)
    }

    /// Saves; on failure `undo` reverts only this call's changes, leaving other unsaved edits in the shared context intact.
    private func saveOrUndo(_ context: ModelContext, undo: () -> Void) throws {
        do {
            try context.save()
        } catch {
            undo()
            throw error
        }
    }

    private func apply(_ edit: SavedEntryEdit, to entry: SavedEntry) {
        entry.date = edit.date
        entry.merchant = edit.merchant
        entry.amount = edit.amount
        entry.category = edit.category
        entry.note = edit.note
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
