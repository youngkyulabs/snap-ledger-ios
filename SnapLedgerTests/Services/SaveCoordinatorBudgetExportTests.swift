// swiftlint:disable force_unwrapping
import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SaveCoordinatorBudgetExportTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveCoordinatorBudgetExportTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func savingEntryAlsoExportsBudgetForThatMonth() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = try makeContext()
        context.insert(AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir)))
        try context.save()

        // 2026-05-15 정오 (Calendar.current).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 15; comps.hour = 12
        let date = Calendar.current.date(from: comps)!

        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_605))
        try context.save()

        let entry = ParsedEntry(date: date, amount: 12_000, merchant: "김밥천국", category: "식비")
        context.insert(entry)
        try context.save()

        let coordinator = SaveCoordinator(categoryLearner: CategoryLearner())
        try coordinator.save(entry, in: context)

        let budgetFile = dir.appendingPathComponent("budgets-2026-05.csv")
        #expect(FileManager.default.fileExists(atPath: budgetFile.path))
        let content = try String(contentsOf: budgetFile, encoding: .utf8)
        #expect(content.contains("식비,300000"))
    }
}
