#if DEBUG
import Foundation
import SwiftData

/// Counts of inserted sample entities.
struct SampleSeedCounts: Equatable {
    let expenses: Int
    let reconciliationMonths: Int
    let budgets: Int
    let reviewItems: Int
}

/// Idempotent seeder applying sample data fixtures to SwiftData.
@MainActor
struct SampleDataSeeder {
    private let reconciliationStore = ReconciliationStore()
    private let budgetStore = CategoryBudgetStore()

    @discardableResult
    func seed(into context: ModelContext) throws -> SampleSeedCounts {
        try clear(in: context)

        let expenseCount = try seedExpenses(into: context)
        try seedReconciliation(SampleDataFixtures.reconciliationHero, month: SampleMonths.hero, in: context)
        try seedReconciliation(SampleDataFixtures.reconciliationCurrent, month: SampleMonths.current, in: context)
        try seedBudgets(into: context)
        let reviewCount = try seedReview(into: context)

        return SampleSeedCounts(
            expenses: expenseCount,
            reconciliationMonths: 2,
            budgets: SampleDataFixtures.budgetLimits.count,
            reviewItems: reviewCount
        )
    }

    func clear(in context: ModelContext) throws {
        let heroFile = CSVWriter.filename(forMonthKey: ReconciliationStore.monthString(from: SampleMonths.hero))
        let currentFile = CSVWriter.filename(
            forMonthKey: ReconciliationStore.monthString(from: SampleMonths.current)
        )
        for entry in try context.fetch(FetchDescriptor<SavedEntry>())
        where entry.csvFile == heroFile || entry.csvFile == currentFile {
            context.delete(entry)
        }
        reconciliationStore.deleteMonth(SampleMonths.hero, in: context)
        reconciliationStore.deleteMonth(SampleMonths.current, in: context)

        let seedCategories = Set(SampleDataFixtures.budgetLimits.map(\.category))
        for budget in try context.fetch(FetchDescriptor<CategoryBudget>())
        where budget.effectiveFrom == SampleMonths.hero && seedCategories.contains(budget.category) {
            context.delete(budget)
        }

        let reviewIDs = Set(SampleDataFixtures.reviewSeeds.compactMap { UUID(uuidString: $0.id) })
        for entry in try context.fetch(FetchDescriptor<ParsedEntry>())
        where reviewIDs.contains(entry.id) {
            context.delete(entry)
        }
        try context.save()
    }

    private func seedExpenses(into context: ModelContext) throws -> Int {
        var seeds = SampleDataParsing.remapSeeds(
            SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero),
            to: SampleMonths.hero
        )
        seeds += SampleDataParsing.droppingFuture(SampleDataParsing.remapSeeds(
            SampleDataParsing.parseExpenses(SampleDataFixtures.expensesCurrent),
            to: SampleMonths.current
        ))
        // Monotonic savedAt ensures predictable display ordering
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, seed) in seeds.enumerated() {
            context.insert(SavedEntry(
                date: seed.date,
                amount: seed.amount,
                merchant: seed.merchant,
                category: seed.category,
                note: seed.note,
                savedAt: base.addingTimeInterval(TimeInterval(index)),
                csvFile: CSVWriter.filename(forMonthKey: CSVWriter.monthKey(for: seed.date))
            ))
        }
        try context.save()
        return seeds.count
    }

    private func seedReconciliation(_ csv: String, month: Int, in context: ModelContext) throws {
        let draft = SampleDataParsing.parseReconciliationDraft(csv)
        _ = try reconciliationStore.save(draft, month: month, in: context)
    }

    private func seedBudgets(into context: ModelContext) throws {
        for seed in SampleDataFixtures.budgetLimits {
            try budgetStore.setLimit(
                seed.monthlyLimit,
                for: seed.category,
                effectiveFrom: SampleMonths.hero,
                in: context
            )
        }
    }

    @discardableResult
    private func seedReview(into context: ModelContext) throws -> Int {
        let seeds = SampleDataFixtures.reviewSeeds
        // createdAt anchors the review date warning, so it tracks now alongside the entry dates
        let now = Date()
        var inserted = 0
        for (index, seed) in seeds.enumerated() {
            guard let uuid = UUID(uuidString: seed.id) else { continue }
            let date = SampleDataParsing.noon(daysAgo: seed.daysAgo, now: now)
            // Descending createdAt keeps the seeded order reverse-chronological
            let createdAt = now.addingTimeInterval(-TimeInterval(index))
            context.insert(ParsedEntry(
                id: uuid,
                date: date,
                amount: seed.amount,
                merchant: seed.merchant,
                category: seed.category,
                note: seed.note,
                sourceImagePath: nil,
                confidence: seed.confidence,
                createdAt: createdAt,
                status: .pending
            ))
            inserted += 1
        }
        try context.save()
        return inserted
    }
}
#endif
