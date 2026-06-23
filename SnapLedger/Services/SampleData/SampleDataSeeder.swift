#if DEBUG
import Foundation
import SwiftData

/// 시딩 결과 건수(알럿 표시·테스트용).
struct SampleSeedCounts: Equatable {
    let expenses: Int
    let reconciliationMonths: Int
    let budgets: Int
}

/// 임베드 샘플 데이터를 SwiftData에 적용/클리어한다. 멱등: seed는 항상 clear 후 삽입.
@MainActor
struct SampleDataSeeder {
    private static let seoulCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()
    private let reconciliationStore = ReconciliationStore()
    private let budgetStore = CategoryBudgetStore()

    @discardableResult
    func seed(into context: ModelContext) throws -> SampleSeedCounts {
        try clear(in: context)

        let expenseCount = try seedExpenses(into: context)
        try seedReconciliation(SampleDataFixtures.reconciliation202605, month: SampleMonths.hero, in: context)
        try seedReconciliation(SampleDataFixtures.reconciliation202606, month: SampleMonths.current, in: context)
        try seedBudgets(into: context)

        return SampleSeedCounts(
            expenses: expenseCount,
            reconciliationMonths: 2,
            budgets: SampleDataFixtures.budgetLimits.count
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
        try context.save()
    }

    private func seedExpenses(into context: ModelContext) throws -> Int {
        var seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
        seeds += SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202606)
        // 같은 날 항목들이 CSV 순서대로 최근 기록 탭에 보이도록 savedAt을 단조 증가시킨다.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, seed) in seeds.enumerated() {
            context.insert(SavedEntry(
                date: seed.date,
                amount: seed.amount,
                merchant: seed.merchant,
                category: seed.category,
                note: seed.note,
                savedAt: base.addingTimeInterval(TimeInterval(index)),
                csvFile: CSVWriter.filename(forMonthKey: CSVWriter.monthKey(for: seed.date, calendar: Self.seoulCalendar))
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
}
#endif
