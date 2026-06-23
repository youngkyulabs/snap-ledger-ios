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
        #expect(counts.reviewItems == 7)

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

    // MARK: - Review (ParsedEntry) seeding tests

    @Test func seedInsertsPendingReviewItems() throws {
        let context = try makeContext()
        let counts = try SampleDataSeeder().seed(into: context)
        #expect(counts.reviewItems == 7)

        let all = try context.fetch(FetchDescriptor<ParsedEntry>())
        #expect(all.count == 7)
        #expect(all.allSatisfy { $0.status == .pending })
    }

    @Test func reviewSeedIsIdempotent() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)
        _ = try SampleDataSeeder().seed(into: context)
        let all = try context.fetch(FetchDescriptor<ParsedEntry>())
        #expect(all.count == 7)
    }

    @Test func clearRemovesReviewItems() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)
        try SampleDataSeeder().clear(in: context)
        let all = try context.fetch(FetchDescriptor<ParsedEntry>())
        #expect(all.isEmpty)
    }

    @Test func clearScopedToSeedIDs() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)

        // Insert a non-seed pending ParsedEntry
        let nonSeedID = UUID()
        let nonSeed = ParsedEntry(
            id: nonSeedID,
            date: .now,
            amount: 1_000,
            merchant: "테스트상점",
            status: .pending
        )
        context.insert(nonSeed)
        try context.save()

        try SampleDataSeeder().clear(in: context)

        let remaining = try context.fetch(FetchDescriptor<ParsedEntry>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == nonSeedID)
    }
}
