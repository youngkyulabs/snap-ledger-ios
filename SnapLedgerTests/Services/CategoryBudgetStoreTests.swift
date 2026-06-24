// swiftlint:disable force_unwrapping

import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
struct CategoryBudgetStoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CategoryBudget.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func monthKeyFromDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        let date = cal.date(from: comps)!
        #expect(CategoryBudgetStore.monthKey(from: date, calendar: cal) == 202_606)
    }

    @Test func resolveReturnsNilWhenNoRecords() {
        #expect(CategoryBudgetStore.resolveLimit(in: [], category: "식비", asOf: 202_606) == nil)
    }

    @Test func resolveCarriesForwardLatestPriorRecord() {
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_601)]
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_603) == 300_000)
    }

    @Test func resolveUsesMostRecentEffectiveRecord() {
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_601),
            CategoryBudget(category: "식비", monthlyLimit: 400_000, effectiveFrom: 202_605),
        ]
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_604) == 300_000)
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_605) == 400_000)
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_607) == 400_000)
    }

    @Test func resolveTombstoneEndsBudgetButPreservesPast() {
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 400_000, effectiveFrom: 202_605),
            CategoryBudget(category: "식비", monthlyLimit: 0, effectiveFrom: 202_606),
        ]
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_605) == 400_000)
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_606) == nil)
    }

    @Test func resolveReturnsNilBeforeFirstRecord() {
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_603)]
        #expect(CategoryBudgetStore.resolveLimit(in: budgets, category: "식비", asOf: 202_602) == nil)
    }

    @Test func setLimitInsertsThenUpdatesSameMonth() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_606, in: ctx)
        try store.setLimit(350_000, for: "식비", effectiveFrom: 202_606, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(all.count == 1)
        #expect(all.first?.monthlyLimit == 350_000)
    }

    @Test func setLimitDifferentMonthsCreatesSeparateRecords() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_601, in: ctx)
        try store.setLimit(400_000, for: "식비", effectiveFrom: 202_605, in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<CategoryBudget>()).count == 2)
    }

    @Test func endBudgetWritesTombstoneWhenBudgeted() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_601, in: ctx)
        try store.endBudget(for: "식비", asOf: 202_606, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(all.count == 2)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_603) == 300_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_606) == nil)
    }

    @Test func endBudgetNoOpWhenNotBudgeted() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.endBudget(for: "식비", asOf: 202_606, in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<CategoryBudget>()).isEmpty)
    }

    @Test func nextMonthKeyRollsOverDecember() {
        #expect(CategoryBudgetStore.nextMonthKey(202_603) == 202_604)
        #expect(CategoryBudgetStore.nextMonthKey(202_612) == 202_701)
        #expect(CategoryBudgetStore.nextMonthKey(202_601) == 202_602)
    }

    @Test func previousMonthKeyRollsBackJanuary() {
        #expect(CategoryBudgetStore.previousMonthKey(202_604) == 202_603)
        #expect(CategoryBudgetStore.previousMonthKey(202_601) == 202_512)
        #expect(CategoryBudgetStore.previousMonthKey(202_612) == 202_611)
    }

    @Test func singleMonthEditConfinesToThatMonthLeavingCurrentUntouched() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_601, in: ctx)
        // 과거 달(3월)만 교정 — 이후 달(현재 6월 포함)은 영향 없어야 한다.
        try store.setLimitForSingleMonth(200_000, for: "식비", month: 202_603, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_602) == 300_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_603) == 200_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_604) == 300_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_606) == 300_000)
    }

    @Test func singleMonthEditWithNoPriorBudgetRestoresNoBudgetAfter() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        // 한도가 전혀 없던 카테고리의 과거 한 달만 채운다.
        try store.setLimitForSingleMonth(200_000, for: "식비", month: 202_603, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_602) == nil)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_603) == 200_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_604) == nil)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_606) == nil)
    }

    @Test func singleMonthReeditKeepsBoundaryStable() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_601, in: ctx)
        try store.setLimitForSingleMonth(200_000, for: "식비", month: 202_603, in: ctx)
        try store.setLimitForSingleMonth(250_000, for: "식비", month: 202_603, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(all.count == 3) // 202601, 202603, 202604(경계)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_603) == 250_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_604) == 300_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_606) == 300_000)
    }

    @Test func singleMonthEditEqualToCarryWritesNoBoundary() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_601, in: ctx)
        try store.setLimitForSingleMonth(300_000, for: "식비", month: 202_603, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(!all.contains { $0.effectiveFrom == 202_604 })
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_606) == 300_000)
    }

    @Test func singleMonthEditDoesNotOverwriteExplicitNextRecord() throws {
        let ctx = try makeContext()
        let store = CategoryBudgetStore()
        try store.setLimit(300_000, for: "식비", effectiveFrom: 202_603, in: ctx)
        try store.setLimit(500_000, for: "식비", effectiveFrom: 202_604, in: ctx)
        try store.setLimitForSingleMonth(200_000, for: "식비", month: 202_603, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<CategoryBudget>())
        #expect(all.count == 2)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_603) == 200_000)
        #expect(CategoryBudgetStore.resolveLimit(in: all, category: "식비", asOf: 202_604) == 500_000)
    }

    @Test func resolveAllKeepsPresetOrderAndDropsZeroAndMissing() {
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_601),
            CategoryBudget(category: "교통", monthlyLimit: 0, effectiveFrom: 202_601), // tombstone → 제외
        ]
        let presets = ["식비", "교통", "문화"] // 문화: 한도 없음 → 제외
        let rows = CategoryBudgetStore.resolveAll(in: budgets, asOf: 202_603, presets: presets)
        #expect(rows == [BudgetCSVRow(category: "식비", limit: 300_000)])
    }

    @Test func resolveAllAppendsOffListCategoriesSortedAfterPresets() {
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_601),
            CategoryBudget(category: "여행", monthlyLimit: 200_000, effectiveFrom: 202_601),
            CategoryBudget(category: "반려동물", monthlyLimit: 50_000, effectiveFrom: 202_601),
        ]
        let presets = ["식비", "교통"]
        let rows = CategoryBudgetStore.resolveAll(in: budgets, asOf: 202_602, presets: presets)
        #expect(rows == [
            BudgetCSVRow(category: "식비", limit: 300_000),
            BudgetCSVRow(category: "반려동물", limit: 50_000),
            BudgetCSVRow(category: "여행", limit: 200_000),
        ])
    }

    @Test func resolveAllIsEmptyWhenNoEffectiveLimits() {
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_606)]
        // asOf가 effectiveFrom보다 이전 → 유효 한도 없음
        #expect(CategoryBudgetStore.resolveAll(in: budgets, asOf: 202_605, presets: ["식비"]).isEmpty)
    }

    @Test func exportBestEffortWritesBudgetFileForMonth() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: [config]))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetExportBestEffort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        context.insert(AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir)))
        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_605))
        try context.save()

        CategoryBudgetStore().exportBestEffort(month: 202_605, in: context)

        let file = dir.appendingPathComponent("budgets-2026-05.csv")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
