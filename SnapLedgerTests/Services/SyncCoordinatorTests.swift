import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            PendingImage.self,
            ParsedEntry.self,
            SavedEntry.self,
            MerchantCategory.self,
            AppSettings.self,
            CSVFileState.self,
            MonthlyReconciliation.self,
            AccountMonthlyBalance.self,
            CashAdjustment.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func configureFolder(_ dir: URL, in context: ModelContext) throws -> AppSettings {
        let settings = AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir))
        context.insert(settings)
        try context.save()
        return settings
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    private func writeCSV(_ dir: URL, _ name: String, _ content: String) throws {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func insertEntry(
        _ context: ModelContext,
        day: Int,
        amount: Int,
        merchant: String,
        category: String? = nil,
        note: String? = nil
    ) {
        context.insert(
            SavedEntry(
                date: makeDate(year: 2026, month: 5, day: day),
                amount: amount,
                merchant: merchant,
                category: category,
                note: note,
                csvFile: "expenses-2026-05.csv"
            )
        )
    }

    @Test func exportThenDetectFindsNoChanges() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 17, amount: 5500, merchant: "스타벅스", category: "카페")
        try context.save()

        try sync.exportAll(in: context)
        let changes = await sync.detectChanges(in: context)
        #expect(changes.isEmpty)
    }

    @Test func writeGuardDetectsConflict() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "A")
        try context.save()
        try sync.exportAll(in: context)

        #expect(sync.checkWriteGuard(monthKeys: ["2026-05"], folderURL: dir, in: context) == .clear)

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-01,A,,9999,\n"
        )
        #expect(
            sync.checkWriteGuard(monthKeys: ["2026-05"], folderURL: dir, in: context)
                == .conflict(["2026-05"])
        )
    }

    @Test func monthStatusesReflectsEachState() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        // 2026-05: 앱 저장 후 export → 일치
        insertEntry(context, day: 1, amount: 100, merchant: "S")
        try context.save()
        try sync.exportAll(in: context)

        // 2026-06: 파일만 존재 → baseline으로 흡수
        try writeCSV(
            dir, "expenses-2026-06.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-06-01,F,,200,\n"
        )
        sync.establishBaselineIfNeeded(in: context)

        // 2026-07: 앱에만 (파일 없음)
        context.insert(
            SavedEntry(
                date: makeDate(year: 2026, month: 7, day: 1),
                amount: 300,
                merchant: "A",
                csvFile: "expenses-2026-07.csv"
            )
        )
        try context.save()

        // 2026-05 파일을 외부에서 변경
        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-01,S,,9999,\n"
        )

        let statuses = await sync.monthStatuses(in: context)
        let byKey = Dictionary(
            uniqueKeysWithValues: statuses.map { ($0.monthKey, $0.state) }
        )
        #expect(byKey["2026-05"] == .externalModified)
        #expect(byKey["2026-06"] == .fileOnly)
        #expect(byKey["2026-07"] == .appOnly)
    }

    @Test func needsResolutionOnlyForDifferences() {
        // 정산 kind로 검증한다(지출은 Phase 2에서 import 비활성 → 별도 테스트).
        func status(_ state: MonthSyncStatus.State) -> MonthSyncStatus {
            MonthSyncStatus(monthKey: "2026-05", kind: .reconciliation, state: state)
        }
        // 맞출 게 없는 상태 — 폴더 상태 화면에서 탭 액션을 주지 않는다.
        #expect(status(.synced).needsResolution == false)
        #expect(status(.notReady).needsResolution == false)
        // 차이가 있는 상태 — 가져오기/저장 액션이 의미 있다.
        #expect(status(.externalModified).needsResolution == true)
        #expect(status(.fileOnly).needsResolution == true)
        #expect(status(.appOnly).needsResolution == true)
    }

    @Test func folderSyncSummaryEmptyWhenNoData() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let summary = await SyncCoordinator().folderSyncSummary(in: context)
        #expect(summary == .empty)
    }

    @Test func folderSyncSummarySyncedAfterExport() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "S")
        try context.save()
        try sync.exportAll(in: context)
        let summary = await sync.folderSyncSummary(in: context)
        #expect(summary == .synced)
    }

    @Test func folderSyncSummaryNeedsSyncOnExternalChange() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "S")
        try context.save()
        try sync.exportAll(in: context)

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-01,S,,9999,\n"
        )
        let summary = await sync.folderSyncSummary(in: context)
        #expect(summary == .needsSync(count: 1))
    }

    @Test func folderMissingWhenFolderDeleted() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "S")
        try context.save()
        try sync.exportAll(in: context)
        let syncedSummary = await sync.folderSyncSummary(in: context)
        #expect(syncedSummary == .synced)
        #expect(sync.isFolderReachable(in: context) == true)

        try FileManager.default.removeItem(at: dir)
        #expect(sync.isFolderReachable(in: context) == false)
        let missingSummary = await sync.folderSyncSummary(in: context)
        #expect(missingSummary == .folderMissing)
    }

    @Test func isFolderReachableNilWhenNoBookmark() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        #expect(SyncCoordinator().isFolderReachable(in: context) == nil)
    }

    // MARK: - Phase 2: 지출 import/감지 비활성 (kind별 분리)

    @Test func monthSyncStatusExpensesNeverAllowsImport() {
        for state in [MonthSyncStatus.State.synced, .externalModified, .fileOnly, .appOnly, .notReady] {
            let s = MonthSyncStatus(monthKey: "2026-06", kind: .expenses, state: state)
            #expect(s.allowsImport == false)
        }
    }

    @Test func monthSyncStatusExpensesFileOnlyNotActionable() {
        // 지출 fileOnly: import도 export도 불가 → 사용자 액션 의미 없음.
        let s = MonthSyncStatus(monthKey: "2026-06", kind: .expenses, state: .fileOnly)
        #expect(s.needsResolution == false)
    }

    @Test func monthSyncStatusReconciliationStillAllowsImport() {
        let s = MonthSyncStatus(monthKey: "2026-06", kind: .reconciliation, state: .fileOnly)
        #expect(s.allowsImport == true)
        #expect(s.needsResolution == true)
    }

    @Test func importExpensesIsNoOp() throws {
        let context = try makeContext()
        let summary = try SyncCoordinator().importMonths(["2026-06"], kind: .expenses, in: context)
        #expect(summary.importedMonths.isEmpty)
        #expect(summary.skippedRows == 0)
    }
}
