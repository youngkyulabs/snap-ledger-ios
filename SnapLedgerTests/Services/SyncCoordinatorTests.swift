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
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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

    @Test func exportThenDetectFindsNoChanges() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        insertEntry(context, day: 17, amount: 5500, merchant: "스타벅스", category: "카페")
        try context.save()

        try sync.exportAll(in: context)
        #expect(sync.detectChanges(in: context).isEmpty)
    }

    @Test func detectsExternalModification() throws {
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

        let changes = sync.detectChanges(in: context)
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

    @Test func baselineAbsorbsExistingFilesThenDetectsNewOnes() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        try writeCSV(
            dir, "expenses-2026-05.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-05-01,A,,100,\n"
        )
        sync.establishBaselineIfNeeded(in: context)
        #expect(sync.detectChanges(in: context).isEmpty)

        try writeCSV(
            dir, "expenses-2026-06.csv",
            "\u{FEFF}날짜,설명,카테고리,금액,메모\n2026-06-01,B,,200,\n"
        )
        let changes = sync.detectChanges(in: context)
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

    @Test func monthStatusesReflectsEachState() throws {
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

        let byKey = Dictionary(
            uniqueKeysWithValues: sync.monthStatuses(in: context).map { ($0.monthKey, $0.state) }
        )
        #expect(byKey["2026-05"] == .externalModified)
        #expect(byKey["2026-06"] == .fileOnly)
        #expect(byKey["2026-07"] == .appOnly)
    }
}
