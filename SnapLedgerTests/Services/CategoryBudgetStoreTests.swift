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
}
