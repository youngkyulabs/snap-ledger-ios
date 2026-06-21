import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "save")

/// 저장된 항목 편집 결과. 모델(`SavedEntry`)은 쓰기가 성공할 때만 바뀌도록,
/// 편집 값을 먼저 이 값으로 넘기고 `update`가 가드 통과 후 대입한다.
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
        // CloudKit이 진실원 — SwiftData 저장이 먼저 성공한다. CSV는 best-effort export.
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

    /// 편집 값을 `edit`으로 받아 모델에 대입하고 저장한다. CloudKit이 진실원이므로
    /// CSV export는 best-effort(폴더 없거나 실패해도 저장은 성공).
    func update(
        _ entry: SavedEntry,
        to edit: SavedEntryEdit,
        in context: ModelContext
    ) throws {
        // entry는 아직 안 바꿨으므로 현재 date가 곧 원래 달.
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

    /// 같은 날짜 항목들의 표시 순서 변경을 영속화한다. `entries`는 새 표시 순서
    /// (savedAt 내림차순 표시 기준)로 받는다. savedAt은 기존 값들의 순열로만 바뀌고,
    /// CSV는 savedAt 순으로 행을 쓰므로 해당 월 파일도 함께 best-effort로 다시 쓴다.
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

    /// 영향받은 달의 CSV를 앱 내용으로 다시 쓴다. CSV는 한 방향 추출물이므로
    /// 폴더가 없거나 쓰기에 실패해도 (이미 커밋된) 저장은 성공으로 둔다 — 로그만 남긴다.
    private func exportEntryBestEffort(monthKeys: [String], in context: ModelContext) {
        guard !monthKeys.isEmpty else { return }
        do {
            try CSVFolderAccess.withFolder(in: context) { folderURL in
                try sync.exportMonths(monthKeys, folderURL: folderURL, in: context)
            }
        } catch CSVFolderAccess.AccessError.noCSVFolder {
            // 폴더 미설정은 정상 상태(옵션) — 조용히 건너뛴다.
        } catch {
            log.error("CSV export(best-effort) failed: \(String(describing: error))")
        }
    }

    /// 가맹점→카테고리 학습은 부가 기능 — 실패해도 (이미 커밋된) 저장을
    /// 실패로 보고하면 사용자가 "저장 안 됨"으로 오인하므로 로그만 남긴다.
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
