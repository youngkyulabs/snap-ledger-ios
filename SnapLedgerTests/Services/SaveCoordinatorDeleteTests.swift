// swiftlint:disable force_unwrapping

import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct SaveCoordinatorDeleteTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self, CSVFileState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeTempFolderWithBookmark(in ctx: ModelContext) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try BookmarkStore.makeBookmark(for: folder)
        let settings = AppSettings(csvFolderBookmark: bookmark)
        ctx.insert(settings)
        try ctx.save()
        return folder
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)!
    }


        let entry = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스", category: "카페")
        ctx.insert(entry)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(entry, in: ctx)

        let saved = try #require(try ctx.fetch(FetchDescriptor<SavedEntry>()).first)
        try coord.delete(saved, in: ctx)

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deleteWithOriginalDateRewritesBothMonthsWhenDateMutated() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let a = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "Old", category: nil)
        let b = ParsedEntry(date: date(2026, 6, 1), amount: 1000, merchant: "Jun", category: nil)
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(a, in: ctx)
        try coord.save(b, in: ctx)

        let saved = try #require(try ctx.fetch(FetchDescriptor<SavedEntry>()).first { $0.merchant == "Old" })
        let originalDate = saved.date
        saved.date = date(2026, 6, 1) // simulate in-flight edit before delete

        try coord.delete(saved, originalDate: originalDate, in: ctx)

        let mayFile = folder.appendingPathComponent("expenses-2026-05.csv")
        let junFile = folder.appendingPathComponent("expenses-2026-06.csv")

        #expect(!FileManager.default.fileExists(atPath: mayFile.path))
        let jun = try String(contentsOf: junFile, encoding: .utf8)
        #expect(!jun.contains("Old"))
        #expect(jun.contains("2026-06-01,Jun,,1000"))
    }

    @Test func saveTwoEntriesIntoSameMonthlyFile() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let a = ParsedEntry(date: date(2026, 5, 17), amount: 1000, merchant: "A", category: nil)
        let b = ParsedEntry(date: date(2026, 5, 18), amount: 2000, merchant: "B", category: nil)
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(a, in: ctx)
        try coord.save(b, in: ctx)

        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        #expect(csv.contains("2026-05-17,A,,1000"))
        #expect(csv.contains("2026-05-18,B,,2000"))
        // Header should appear exactly once
        let headerCount = csv.components(separatedBy: "날짜,설명,카테고리,금액").count - 1
        #expect(headerCount == 1)
    }
}
}
