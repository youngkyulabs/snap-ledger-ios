import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SampleDataSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: config)
        return ModelContext(container)
    }

    @Test func seedInsertsExpectedCounts() throws {
        let context = try makeContext()
        let counts = try SampleDataSeeder().seed(into: context)
        #expect(counts.expenses == 56) // 5월 37 + 6월 19
        #expect(counts.reconciliationMonths == 2)
        #expect(counts.budgets == 9)

        let entries = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(entries.count == 56)
        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        #expect(budgets.count == 9)
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
        #expect(incomes.count == 3) // 5월 2 + 6월 1
    }

    @Test func seedIsIdempotent() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)
        _ = try SampleDataSeeder().seed(into: context)
        #expect(try context.fetch(FetchDescriptor<SavedEntry>()).count == 56)
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).count == 9)
        #expect(try context.fetch(FetchDescriptor<IncomeItem>()).count == 3)
    }

    @Test func clearRemovesSampleScope() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)
        try SampleDataSeeder().clear(in: context)
        #expect(try context.fetch(FetchDescriptor<SavedEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MonthlyReconciliation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<IncomeItem>()).isEmpty)
    }
}
