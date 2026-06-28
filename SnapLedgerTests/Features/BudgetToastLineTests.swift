// swiftlint:disable force_unwrapping

import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct BudgetToastLineTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        return ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func saved(_ y: Int, _ m: Int, _ d: Int, amount: Int, category: String) -> SavedEntry {
        SavedEntry(date: date(y, m, d), amount: amount, merchant: "M", category: category,
                   savedAt: date(y, m, d), csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv")
    }

    @Test func returnsLineWhenBudgetExists() throws {
        let ctx = try makeContext()
        ctx.insert(CategoryBudget(category: "식비", monthlyLimit: 150_000, effectiveFrom: 202_606))
        ctx.insert(saved(2026, 6, 10, amount: 120_000, category: "식비"))
        try ctx.save()

        let line = BudgetProgress.line(for: "식비", asOf: 202_606, in: ctx)
        #expect(line?.spent == 120_000)
        #expect(line?.limit == 150_000)
        #expect(line?.remaining == 30_000)
        #expect(line?.state == .near)
    }

    @Test func nilWhenNoBudget() throws {
        let ctx = try makeContext()
        ctx.insert(saved(2026, 6, 10, amount: 10_000, category: "카페"))
        try ctx.save()
        #expect(BudgetProgress.line(for: "카페", asOf: 202_606, in: ctx) == nil)
    }

    @Test func nilWhenTombstone() throws {
        let ctx = try makeContext()
        ctx.insert(CategoryBudget(category: "식비", monthlyLimit: 0, effectiveFrom: 202_606))
        ctx.insert(saved(2026, 6, 10, amount: 50_000, category: "식비"))
        try ctx.save()
        #expect(BudgetProgress.line(for: "식비", asOf: 202_606, in: ctx) == nil)
    }
}
