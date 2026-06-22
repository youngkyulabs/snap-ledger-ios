import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorReconciliationTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncCoordinatorReconciliationTests-\(UUID().uuidString)", isDirectory: true)
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

    @Test func exportReconciliationMonthWritesFile() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000))
        context.insert(CardUsageItem(monthKey: 202_605, title: "카드 사용액", amount: 450_000))
        context.insert(SavingsItem(monthKey: 202_605, title: "저축액", amount: 500_000))
        context.insert(
            AccountMonthlyBalance(
                monthKey: 202_605,
                accountName: "입출금",
                openingBalance: 1_000_000,
                closingBalance: 2_000_000
            )
        )
        try context.save()

        try sync.exportReconciliationMonths(["2026-05"], folderURL: dir, in: context)

        let content = try String(
            contentsOf: dir.appendingPathComponent("reconciliations-2026-05.csv"),
            encoding: .utf8
        )
        #expect(content.contains("수입,월급,,,3000000,"))
        #expect(content.contains("저축액,저축액,,,500000,"))
        #expect(content.contains("기초잔액,,입출금,,1000000,"))
        #expect(content.contains("카드사용액,카드 사용액,,,450000,"))
    }

    @Test func exportWritesCardItemsAsSeparateRows() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(CardUsageItem(monthKey: 202_605, title: "신한", amount: 300_000, sortOrder: 0))
        context.insert(CardUsageItem(monthKey: 202_605, title: "현대", amount: 200_000, sortOrder: 1))
        try context.save()

        try sync.exportReconciliationMonths(["2026-05"], folderURL: dir, in: context)

        let content = try String(
            contentsOf: dir.appendingPathComponent("reconciliations-2026-05.csv"),
            encoding: .utf8
        )
        #expect(content.contains("카드사용액,신한,,,300000,"))
        #expect(content.contains("카드사용액,현대,,,200000,"))
    }

    @Test func reconciliationMonthKeysCollectsAllModels() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_606, title: "월급", amount: 1))
        context.insert(SavingsItem(monthKey: 202_604, title: "적금", amount: 1))
        try context.save()

        let keys = SyncCoordinator().reconciliationMonthKeys(in: context)
        #expect(keys == ["2026-05", "2026-06", "2026-04"])
    }
}
