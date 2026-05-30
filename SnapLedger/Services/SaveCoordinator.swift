import Foundation
import SwiftData

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
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 골라주세요."
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
            try CSVWriter(folder: folderURL).append(row)

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

            try learnCategoryIfPresent(merchant: entry.merchant, category: entry.category, in: context)

            entry.status = .dismissed
            sync.refreshFileState(monthKey: monthKey, folderURL: folderURL, in: context)
            try context.save()
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

            // 가드 통과 후에만 모델을 변경한다.
            entry.date = edit.date
            entry.merchant = edit.merchant
            entry.amount = edit.amount
            entry.category = edit.category
            entry.note = edit.note
            entry.csvFile = CSVWriter.filename(forMonthKey: newKey)
            try context.save()

            try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)
            try learnCategoryIfPresent(merchant: entry.merchant, category: entry.category, in: context)
            try context.save()
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

            context.delete(entry)
            try context.save()

            try sync.exportMonths(affectedKeys, folderURL: folderURL, in: context)
            try context.save()
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

    private func learnCategoryIfPresent(
        merchant: String,
        category: String?,
        in context: ModelContext
    ) throws {
        if let category, !category.isEmpty {
            try categoryLearner.learn(merchant: merchant, category: category, in: context)
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
