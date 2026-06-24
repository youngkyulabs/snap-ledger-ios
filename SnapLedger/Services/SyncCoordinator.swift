import Foundation
import SwiftData

/// SwiftData(CloudKit 진실원)를 월별 CSV로 **한 방향 내보내기**한다.
/// CloudKit이 모든 영속 데이터의 진실원이므로 CSV는 AI 분석·백업용 추출물이다.
/// 파일→앱 import·외부 변경 감지·충돌 해소는 Phase 4에서 제거됐다.
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

    /// 저장 폴더에 실제 접근 가능한지. bookmark는 있으나 폴더가 삭제/이동된 경우 false.
    /// 폴더 미설정이면 nil.
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

    // MARK: - Export (앱 → 파일, 한 방향)

    /// 앱에 있는 모든 지출·정산 달을 폴더로 내보낸다(수동 전체 내보내기·새 폴더 백필용).
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

    /// 폴더를 이미 연 호출자(`SaveCoordinator`)용. security scope를 새로 열지 않는다.
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

    // MARK: - 폴더 접근

    /// 폴더 접근(resolve·scope·도달성·stale 갱신)은 `CSVFolderAccess`에 위임하고,
    /// 그 중립 에러를 사용자 노출용 `SyncError`로 매핑한다.
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
