import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
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

    private func insertEntry(
        _ context: ModelContext,
        day: Int,
        amount: Int,
        merchant: String,
        category: String? = nil
    ) {
        context.insert(
            SavedEntry(
                date: makeDate(year: 2026, month: 5, day: day),
                amount: amount,
                merchant: merchant,
                category: category,
                csvFile: "expenses-2026-05.csv"
            )
        )
    }

    @Test func exportAllWritesMonthCSV() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        insertEntry(context, day: 17, amount: 5500, merchant: "스타벅스", category: "카페")
        try context.save()

        try SyncCoordinator().exportAll(in: context)

        let file = dir.appendingPathComponent("expenses-2026-05.csv")
        #expect(FileManager.default.fileExists(atPath: file.path))
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("스타벅스"))
        #expect(content.contains("5500"))
    }

    @Test func exportWithoutFolderThrows() throws {
        let context = try makeContext()
        insertEntry(context, day: 1, amount: 100, merchant: "A")
        try context.save()
        #expect(throws: SyncCoordinator.SyncError.self) {
            try SyncCoordinator().exportAll(in: context)
        }
    }

    @Test func isFolderReachableNilWhenNoBookmark() throws {
        let context = try makeContext()
        context.insert(AppSettings())
        try context.save()
        #expect(SyncCoordinator().isFolderReachable(in: context) == nil)
    }

    @Test func isFolderReachableFalseAfterFolderDeleted() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        #expect(SyncCoordinator().isFolderReachable(in: context) == true)

        try FileManager.default.removeItem(at: dir)
        #expect(SyncCoordinator().isFolderReachable(in: context) == false)
    }
}
