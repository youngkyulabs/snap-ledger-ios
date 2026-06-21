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

    @Test func detectsExternalModification() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 17, amount: 5500, merchant: "스타벅스", category: "카페")
        try context.save()
        try sync.exportAll(in: context)

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-17,스타벅스,카페,9999,\n"
        )

        let changes = await sync.detectChanges(in: context)
        #expect(changes.count == 1)
        #expect(changes.first?.monthKey == "2026-05")
        #expect(changes.first?.kind == .modified)
    }

    @Test func importReplacesMonthFromFile() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "기존")
        try context.save()

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-17,스타벅스,카페,5500,\n2026-05-18,김밥,식비,8000,\n"
        )

        let summary = try sync.importMonths(["2026-05"], in: context)
        #expect(summary.totalRows == 2)

        let saved = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 2)
        #expect(!saved.contains { $0.merchant == "기존" })
        #expect(saved.contains { $0.merchant == "스타벅스" && $0.amount == 5500 })
    }

    @Test func importSkipsMalformedMonthAndKeepsAppData() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "기존")
        try context.save()

        // 닫히지 않은 따옴표 — 외부 편집기에서 구조가 깨진 파일.
        // 이걸로 그 달을 교체하면 행이 잘려 들어오므로 건너뛰어야 한다.
        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-17,\"스타벅스,카페,5500,\n"
        )

        let summary = try sync.importMonths(["2026-05"], in: context)
        #expect(summary.malformedMonths == ["2026-05"])
        #expect(summary.importedMonths.isEmpty)
        #expect(summary.skipNotice != nil)

        let saved = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.merchant == "기존")
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

    @Test func baselineAbsorbsExistingFilesThenDetectsNewOnes() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-01,A,,100,\n"
        )
        sync.establishBaselineIfNeeded(in: context)
        let baselineChanges = await sync.detectChanges(in: context)
        #expect(baselineChanges.isEmpty)

        try writeCSV(
            dir, "expenses-2026-06.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-06-01,B,,200,\n"
        )
        let changes = await sync.detectChanges(in: context)
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .externalNew)
        #expect(changes.first?.monthKey == "2026-06")
    }

    @Test func importReportsSkippedRows() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\nBAD,A,,100,\n2026-05-02,B,,300,\n"
        )
        let summary = try sync.importMonths(["2026-05"], in: context)
        #expect(summary.totalRows == 1)
        #expect(summary.skippedRows == 1)
    }

    @Test func importSkipsUnreadableMonthWithoutWiping() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 1, amount: 100, merchant: "기존")
        try context.save()

        // 비-UTF8 파일 → 읽기 불가. "빈 파일"로 오판해 그 달을 비우면 안 된다.
        try Data([0xFF, 0xFE, 0x41]).write(
            to: dir.appendingPathComponent("expenses-2026-05.csv"), options: .atomic
        )

        let summary = try sync.importMonths(["2026-05"], in: context)
        #expect(summary.unreadableMonths == ["2026-05"])
        #expect(summary.importedMonths.isEmpty)

        let saved = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.merchant == "기존")
    }

    @Test func exportImportRoundTripPreservesValues() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 3, amount: 4200, merchant: "투썸", category: "카페", note: "라떼")
        try context.save()
        try sync.exportAll(in: context)

        for entry in try context.fetch(FetchDescriptor<SavedEntry>()) {
            context.delete(entry)
        }
        try context.save()

        let summary = try sync.importAll(in: context)
        #expect(summary.totalRows == 1)

        let saved = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.merchant == "투썸")
        #expect(saved.first?.category == "카페")
        #expect(saved.first?.note == "라떼")
        #expect(saved.first?.amount == 4200)
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
        func status(_ state: MonthSyncStatus.State) -> MonthSyncStatus {
            MonthSyncStatus(monthKey: "2026-05", state: state)
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
}
