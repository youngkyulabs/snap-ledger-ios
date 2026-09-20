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

    /// Current-month rows dated after today are dropped, so the expected total moves with the calendar.
    private var expectedExpenseCount: Int {
        let today = Calendar.current.startOfDay(for: .now)
        let current = SampleDataParsing.droppingFuture(SampleDataParsing.remapSeeds(
            SampleDataParsing.parseExpenses(SampleDataFixtures.expensesCurrent),
            to: SampleMonths.current
        ))
        #expect(current.allSatisfy { Calendar.current.startOfDay(for: $0.date) <= today })
        return 37 + current.count
    }

    @Test func seedInsertsExpectedCounts() throws {
        let context = try makeContext()
        let counts = try SampleDataSeeder().seed(into: context)
        #expect(counts.expenses == expectedExpenseCount) // hero month (37) + current month to date
        #expect(counts.reconciliationMonths == 2)
        #expect(counts.budgets == 9)
        #expect(counts.reviewItems == 7)

        let entries = try context.fetch(FetchDescriptor<SavedEntry>())
        #expect(entries.count == expectedExpenseCount)
        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        #expect(budgets.count == 9)
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
        #expect(incomes.count == 3) // May (2) + June (1)
    }

    @Test func seedIsIdempotent() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)
        _ = try SampleDataSeeder().seed(into: context)
        #expect(try context.fetch(FetchDescriptor<SavedEntry>()).count == expectedExpenseCount)
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

    @Test func seededEntriesLandInHeroAndCurrentMonthsWithoutFutureDates() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let months = Set([SampleMonths.hero, SampleMonths.current])
        let entries = try context.fetch(FetchDescriptor<SavedEntry>())
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            #expect(months.contains((comps.year ?? 0) * 100 + (comps.month ?? 0)))
            #expect(calendar.startOfDay(for: entry.date) <= today)
        }
        let heroMonth = SampleMonths.hero % 100
        #expect(entries.contains { calendar.component(.month, from: $0.date) == heroMonth })
    }

    @Test func seededReviewItemsShowNoDateWarning() throws {
        let context = try makeContext()
        _ = try SampleDataSeeder().seed(into: context)

        let all = try context.fetch(FetchDescriptor<ParsedEntry>())
        #expect(all.count == 7)
        for entry in all {
            #expect(!ReviewDateCheck.status(for: entry.date, now: entry.createdAt).isWarning)
        }
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
