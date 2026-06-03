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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
}
