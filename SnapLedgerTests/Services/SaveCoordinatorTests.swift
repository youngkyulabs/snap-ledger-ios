// swiftlint:disable force_unwrapping

import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct SaveCoordinatorTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

    @Test func saveAppendsToCSVAndCreatesSavedEntry() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let entry = ParsedEntry(
            date: date(2026, 5, 17),
            amount: 5000,
            merchant: "스타벅스",
            category: "카페"
        )
        ctx.insert(entry)
        try ctx.save()

        try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: ctx)

        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        #expect(csv.contains("2026-05-17,스타벅스,카페,5000"))

        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.csvFile == "expenses-2026-05.csv")

        #expect(entry.status == .dismissed)
    }

    @Test func savePropagatesNoteToCSVAndSavedEntry() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let entry = ParsedEntry(
            date: date(2026, 5, 17),
            amount: 5000,
            merchant: "스타벅스",
            category: "카페",
            note: "팀 회의"
        )
        ctx.insert(entry)
        try ctx.save()

        try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: ctx)

        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        #expect(csv.contains("2026-05-17,스타벅스,카페,5000,팀 회의"))

        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.first?.note == "팀 회의")
    }

    @Test func saveLearnsMerchantCategoryMapping() throws {
        let ctx = try makeContext()
        _ = try makeTempFolderWithBookmark(in: ctx)

        let entry = ParsedEntry(
            date: date(2026, 5, 17),
            amount: 3000,
            merchant: "GS25",
            category: "편의점"
        )
        ctx.insert(entry)
        try ctx.save()

        try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: ctx)

        let learned = try CategoryLearner().category(for: "GS25", in: ctx)
        #expect(learned == "편의점")
    }

    // Phase 2: CloudKit이 진실원 — 폴더가 없거나(설정 안 됨) 폴더가 삭제됐어도 저장은 성공한다.
    // CSV export는 best-effort라 조용히 건너뛴다(저장 실패로 보고하지 않음).
    // (폴더 미설정 성공 케이스는 saveSucceedsWithoutCSVFolder가 별도로 검증.)
    @Test func saveSucceedsWhenFolderDeleted() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)
        try FileManager.default.removeItem(at: folder)
        let entry = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스")
        ctx.insert(entry)
        try ctx.save()

        try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: ctx)

        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.merchant == "스타벅스")
    }

    @Test func updateRewritesCSVForSameMonthEdit() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let a = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스", category: "카페")
        let b = ParsedEntry(date: date(2026, 5, 18), amount: 3000, merchant: "GS25", category: "편의점")
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(a, in: ctx)
        try coord.save(b, in: ctx)

        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        let target = try #require(saved.first { $0.merchant == "스타벅스" })

        try coord.update(
            target,
            to: SavedEntryEdit(
                date: target.date,
                merchant: target.merchant,
                amount: 7500,
                category: "식비",
                note: target.note
            ),
            in: ctx
        )

        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        let headerCount = csv.components(separatedBy: "날짜,설명,카테고리,금액").count - 1
        #expect(headerCount == 1)
        #expect(csv.contains("2026-05-17,스타벅스,식비,7500"))
        #expect(csv.contains("2026-05-18,GS25,편의점,3000"))
        #expect(!csv.contains(",카페,5000"))
    }

    @Test func updateMovesEntryToDifferentMonthFile() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let entry = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스", category: "카페")
        ctx.insert(entry)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(entry, in: ctx)

        let saved = try #require(try ctx.fetch(FetchDescriptor<SavedEntry>()).first)

        try coord.update(
            saved,
            to: SavedEntryEdit(
                date: date(2026, 6, 1),
                merchant: saved.merchant,
                amount: saved.amount,
                category: saved.category,
                note: saved.note
            ),
            in: ctx
        )

        let mayFile = folder.appendingPathComponent("expenses-2026-05.csv")
        let junFile = folder.appendingPathComponent("expenses-2026-06.csv")

        #expect(!FileManager.default.fileExists(atPath: mayFile.path))
        #expect(FileManager.default.fileExists(atPath: junFile.path))

        let junCSV = try String(contentsOf: junFile, encoding: .utf8)
        #expect(junCSV.contains("2026-06-01,스타벅스,카페,5000"))
        #expect(saved.date == date(2026, 6, 1))
        #expect(saved.csvFile == "expenses-2026-06.csv")
    }

    // Phase 2: CloudKit이 진실원 — CSV 쓰기가 실패해도(폴더 삭제 등) update는 성공하고
    // 변경이 DB에 영속된다. CSV export는 best-effort라 저장을 롤백하지 않는다.
    @Test func updateSucceedsAndPersistsWhenCSVWriteFails() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let entry = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스", category: "카페")
        ctx.insert(entry)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(entry, in: ctx)
        let saved = try #require(try ctx.fetch(FetchDescriptor<SavedEntry>()).first)

        // 폴더를 지워 CSV 쓰기를 실패시킨다.
        try FileManager.default.removeItem(at: folder)

        // throw 없이 성공해야 한다.
        try coord.update(
            saved,
            to: SavedEntryEdit(
                date: date(2026, 6, 1),
                merchant: "바뀐상호",
                amount: 9999,
                category: "식비",
                note: "메모"
            ),
            in: ctx
        )

        // 변경은 모델과 DB에 영속된다(CSV 실패와 무관).
        #expect(saved.merchant == "바뀐상호")
        #expect(saved.amount == 9999)
        #expect(saved.date == date(2026, 6, 1))
        #expect(saved.csvFile == "expenses-2026-06.csv")
        let persisted = try #require(
            try ModelContext(ctx.container).fetch(FetchDescriptor<SavedEntry>()).first
        )
        #expect(persisted.merchant == "바뀐상호")
        #expect(persisted.amount == 9999)
    }

    @Test func saveSucceedsWithoutCSVFolder() throws {
        // 기존 makeContext() 재사용(SavedEntry 포함, cloudKitDatabase:.none). 폴더 북마크는 만들지 않는다.
        let context = try makeContext()
        context.insert(AppSettings())  // 폴더 미설정 settings
        try context.save()

        let coordinator = SaveCoordinator(categoryLearner: CategoryLearner())
        let entry = ParsedEntry(date: .now, amount: 4200, merchant: "김밥천국", category: "식비", note: nil)
        context.insert(entry)

        // 폴더가 없어도 throw 없이 저장되어야 한다.
        try coordinator.save(entry, in: context)

        let saved = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.merchant == "김밥천국")
    }

    @Test func deleteRemovesEntryAndRewritesCSV() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)

        let a = ParsedEntry(date: date(2026, 5, 17), amount: 5000, merchant: "스타벅스", category: "카페")
        let b = ParsedEntry(date: date(2026, 5, 18), amount: 3000, merchant: "GS25", category: "편의점")
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        try coord.save(a, in: ctx)
        try coord.save(b, in: ctx)

        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        let target = try #require(saved.first { $0.merchant == "스타벅스" })

        try coord.delete(target, in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<SavedEntry>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.merchant == "GS25")

        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        #expect(!csv.contains("스타벅스"))
        #expect(csv.contains("2026-05-18,GS25,편의점,3000"))
    }
}
