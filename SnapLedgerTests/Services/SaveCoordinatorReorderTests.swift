// swiftlint:disable force_unwrapping

import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct SaveCoordinatorReorderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self, CSVFileState.self,
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

    private struct Fixture {
        let a: SavedEntry
        let b: SavedEntry
        let c: SavedEntry
        let base: Date
    }

    /// 같은 날짜에 A→B→C 순으로 저장된 세 항목을 만들고 savedAt을 결정적으로 부여한다.
    private func makeThreeEntries(
        coord: SaveCoordinator,
        in ctx: ModelContext
    ) throws -> Fixture {
        for name in ["A", "B", "C"] {
            let parsed = ParsedEntry(date: date(2026, 5, 17), amount: 1000, merchant: name, category: nil)
            ctx.insert(parsed)
            try ctx.save()
            try coord.save(parsed, in: ctx)
        }
        let saved = try ctx.fetch(FetchDescriptor<SavedEntry>())
        let base = date(2026, 5, 17)
        let fixture = Fixture(
            a: try #require(saved.first { $0.merchant == "A" }),
            b: try #require(saved.first { $0.merchant == "B" }),
            c: try #require(saved.first { $0.merchant == "C" }),
            base: base
        )
        fixture.a.savedAt = base
        fixture.b.savedAt = base.addingTimeInterval(60)
        fixture.c.savedAt = base.addingTimeInterval(120)
        try ctx.save()
        return fixture
    }

    @Test func reorderPersistsDisplayOrderAndRewritesCSVRows() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)
        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        let fx = try makeThreeEntries(coord: coord, in: ctx)

        // 표시(내림차순)는 [C, B, A]. C와 B를 바꿔 [B, C, A]로 재배열.
        try coord.reorder([fx.b, fx.c, fx.a], in: ctx)

        #expect(fx.b.savedAt > fx.c.savedAt)
        #expect(fx.c.savedAt > fx.a.savedAt)
        // 새 savedAt은 기존 값들의 순열 — 다른 날·다른 달과 간섭하지 않는다.
        let expected = Set([fx.base, fx.base.addingTimeInterval(60), fx.base.addingTimeInterval(120)])
        #expect(Set([fx.a.savedAt, fx.b.savedAt, fx.c.savedAt]) == expected)

        // CSV는 savedAt 오름차순으로 다시 쓰인다 → 행 순서 [A, C, B].
        let csv = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        let merchants = csv.split(separator: "\n")
            .filter { !$0.contains("날짜") }
            .map { String($0.split(separator: ",", omittingEmptySubsequences: false)[1]) }
        #expect(merchants == ["A", "C", "B"])
    }

    @Test func reorderExportFailureRestoresSavedAt() throws {
        let ctx = try makeContext()
        let folder = try makeTempFolderWithBookmark(in: ctx)
        let coord = SaveCoordinator(categoryLearner: CategoryLearner())
        let fx = try makeThreeEntries(coord: coord, in: ctx)

        // 폴더는 살아 있어 충돌 가드는 통과하지만, 읽기 전용이라 CSV 쓰기 자체가 실패하는 상황.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }

        #expect(throws: (any Error).self) {
            try coord.reorder([fx.b, fx.c, fx.a], in: ctx)
        }

        // 파일을 고치지 못했으면 앱 안 순서도 원래대로 남아야 한다.
        #expect(fx.a.savedAt == fx.base)
        #expect(fx.b.savedAt == fx.base.addingTimeInterval(60))
        #expect(fx.c.savedAt == fx.base.addingTimeInterval(120))
    }
}
