import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorBudgetTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncCoordinatorBudgetTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func exportBudgetMonthWritesResolvedLimits() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = try makeContext()
        let sync = SyncCoordinator()

        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_605))
        try context.save()

        try sync.exportBudgetMonths(["2026-05"], folderURL: dir, in: context)

        let content = try String(
            contentsOf: dir.appendingPathComponent("budgets-2026-05.csv"),
            encoding: .utf8
        )
        #expect(content.contains("카테고리,한도"))
        #expect(content.contains("식비,300000"))
    }

    @Test func exportBudgetMonthRemovesFileWhenNoLimits() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = try makeContext()
        let sync = SyncCoordinator()

        // 먼저 파일을 만든다.
        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_605))
        try context.save()
        try sync.exportBudgetMonths(["2026-05"], folderURL: dir, in: context)
        let file = dir.appendingPathComponent("budgets-2026-05.csv")
        #expect(FileManager.default.fileExists(atPath: file.path))

        // 그 달부터 해제(tombstone) → 파일 제거. 실제 앱과 동일하게 upsert(setLimit) 사용.
        try CategoryBudgetStore().setLimit(0, for: "식비", effectiveFrom: 202_605, in: context)
        try sync.exportBudgetMonths(["2026-05"], folderURL: dir, in: context)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func budgetMonthKeysCoversCarryForwardRange() throws {
        let context = try makeContext()
        let sync = SyncCoordinator()

        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_603))
        try context.save()

        // 2026-03부터 effectiveFrom, asOf 2026-06 → 03,04,05,06 (이월 포함).
        let keys = sync.budgetMonthKeys(asOf: 202_606, in: context)
        #expect(keys == ["2026-03", "2026-04", "2026-05", "2026-06"])
    }

    @Test func budgetMonthKeysEmptyWhenNoBudgets() throws {
        let context = try makeContext()
        let sync = SyncCoordinator()
        #expect(sync.budgetMonthKeys(asOf: 202_606, in: context).isEmpty)
    }

    @discardableResult
    private func configureFolder(_ dir: URL, in context: ModelContext) throws -> AppSettings {
        let settings = AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir))
        context.insert(settings)
        try context.save()
        return settings
    }

    @Test func exportAllBackfillsBudgetMonths() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        let current = CategoryBudgetStore.monthKey(from: Date())
        let prev = CategoryBudgetStore.previousMonthKey(current)
        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: prev))
        try context.save()

        try sync.exportAll(in: context)

        // 이전 달·현재 달 모두 이월된 한도로 파일이 생긴다.
        let prevFile = dir.appendingPathComponent("budgets-\(SyncCoordinator.monthKeyString(from: prev)).csv")
        let currentFile = dir.appendingPathComponent("budgets-\(SyncCoordinator.monthKeyString(from: current)).csv")
        #expect(FileManager.default.fileExists(atPath: prevFile.path))
        #expect(FileManager.default.fileExists(atPath: currentFile.path))
        let content = try String(contentsOf: currentFile, encoding: .utf8)
        #expect(content.contains("식비,300000"))
    }
}
