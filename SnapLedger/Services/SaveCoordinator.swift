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

    enum CoordinatorError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case externalConflict(months: [String])
        case fileNotReady(months: [String])
        case folderUnavailable

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 선택해 주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            case .externalConflict(let months):
                "\(CSVWriter.monthLabels(months)) 파일이 앱 밖에서 변경됐어요. 먼저 가져오거나 덮어쓸지 선택해 주세요."
            case .fileNotReady(let months):
                "\(CSVWriter.monthLabels(months)) 파일을 아직 받아오는 중이에요. 잠시 후 다시 시도해 주세요."
            case .folderUnavailable:
                "저장 폴더를 찾을 수 없어요. 폴더가 삭제됐거나 이동했을 수 있어요. 설정 → 저장 폴더에서 다시 선택해 주세요."
            }
        }
    }

    func save(
        _ entry: ParsedEntry,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        try withFolder(in: context) { folderURL in
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
            let originalStatus = entry.status
            entry.status = .dismissed
            do {
                try CSVWriter(folder: folderURL).append(row)
                sync.refreshFileState(monthKey: monthKey, folderURL: folderURL, in: context)
                try context.save()
            } catch {
                // rollback()은 pending insert/delete는 버리지만 등록된 객체의
                // 속성 변경은 메모리에 남길 수 있어 원본 값을 직접 복원한다.
                context.rollback()
                entry.status = originalStatus
                throw error
            }
            learnCategoryBestEffort(merchant: entry.merchant, category: entry.category, in: context)
        }
    }

    /// 편집 값을 `edit`으로 받아, 충돌 가드를 통과한 뒤에만 `entry`에 대입한다.
    /// 쓰기가 실패하면 `entry`는 더티로 남지 않아 앱↔파일이 어긋나지 않는다.
    func update(
        _ entry: SavedEntry,
        to edit: SavedEntryEdit,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        try withFolder(in: context) { folderURL in
            // entry는 아직 안 바꿨으므로 현재 date가 곧 원래 달.
            let oldKey = CSVWriter.monthKey(for: entry.date)
            let newKey = CSVWriter.monthKey(for: edit.date)
            let affectedKeys = Array(Set([oldKey, newKey]))

            if !ignoringConflict {
                try ensureNoConflict(monthKeys: affectedKeys, folderURL: folderURL, in: context)
            }

            // 가드 통과 후에만 모델을 변경하고, CSV 쓰기까지 성공해야 커밋한다.
            // 쓰기 실패 시 되돌림 — DB만 바뀌고 파일·지문은 그대로인 "감지 불가능한
            // 어긋남"(지문이 파일과 일치해 외부 변경으로도 안 잡힘)을 막는다.
            let original = SavedEntryEdit(
                date: entry.date,
                merchant: entry.merchant,
                amount: entry.amount,
                category: entry.category,
                note: entry.note
            )
            let originalFile = entry.csvFile
            entry.date = edit.date
            entry.merchant = edit.merchant
            entry.amount = edit.amount
            entry.category = edit.category
            entry.note = edit.note
            entry.csvFile = CSVWriter.filename(forMonthKey: newKey)
            do {
                try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)
                try context.save()
            } catch {
                // rollback()은 pending insert/delete는 버리지만 등록된 객체의
                // 속성 변경은 메모리에 남길 수 있어 원본 값을 직접 복원한다.
                context.rollback()
                entry.date = original.date
                entry.merchant = original.merchant
                entry.amount = original.amount
                entry.category = original.category
                entry.note = original.note
                entry.csvFile = originalFile
                throw error
            }
            learnCategoryBestEffort(merchant: entry.merchant, category: entry.category, in: context)
        }
    }

    func delete(
        _ entry: SavedEntry,
        originalDate: Date? = nil,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        try withFolder(in: context) { folderURL in
            let currentKey = CSVWriter.monthKey(for: entry.date)
            let oldKey = CSVWriter.monthKey(for: originalDate ?? entry.date)
            let affectedKeys = Array(Set([oldKey, currentKey]))

            if !ignoringConflict {
                try ensureNoConflict(monthKeys: affectedKeys, folderURL: folderURL, in: context)
            }

            // 삭제도 CSV 쓰기까지 성공해야 커밋한다 (update와 같은 이유).
            context.delete(entry)
            do {
                try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// 같은 날짜 항목들의 표시 순서 변경을 영속화한다. `entries`는 새 표시 순서
    /// (savedAt 내림차순 표시 기준)로 받는다. savedAt은 기존 값들의 순열로만 바뀌고,
    /// CSV는 savedAt 순으로 행을 쓰므로 해당 월 파일도 함께 다시 쓴다.
    func reorder(
        _ entries: [SavedEntry],
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws {
        guard entries.count > 1 else { return }
        try withFolder(in: context) { folderURL in
            let monthKeys = Array(Set(entries.map { CSVWriter.monthKey(for: $0.date) }))
            if !ignoringConflict {
                try ensureNoConflict(monthKeys: monthKeys, folderURL: folderURL, in: context)
            }

            let originals = entries.map(\.savedAt)
            let stamps = EntryReorder.descendingTimestamps(from: originals)
            for (entry, stamp) in zip(entries, stamps) {
                entry.savedAt = stamp
            }
            do {
                try sync.exportMonths(monthKeys, folderURL: folderURL, in: context)
                try context.save()
            } catch {
                // rollback()은 등록된 객체의 속성 변경을 메모리에 남길 수 있어 원본 값을 직접 복원한다.
                context.rollback()
                for (entry, original) in zip(entries, originals) {
                    entry.savedAt = original
                }
                throw error
            }
        }
    }

    /// 폴더 접근(resolve·scope·도달성·stale 갱신)은 `CSVFolderAccess`에 위임하고,
    /// 그 중립 에러를 사용자 노출용 `CoordinatorError`로 매핑한다. save/update/delete 공통.
    private func withFolder(
        in context: ModelContext,
        _ body: (URL) throws -> Void
    ) throws {
        do {
            try CSVFolderAccess.withFolder(in: context, body)
        } catch let error as CSVFolderAccess.AccessError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: CSVFolderAccess.AccessError) -> CoordinatorError {
        switch error {
        case .noCSVFolder: .noCSVFolder
        case .bookmarkResolveFailed(let underlying): .bookmarkResolveFailed(underlying: underlying)
        case .folderUnavailable: .folderUnavailable
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
}
