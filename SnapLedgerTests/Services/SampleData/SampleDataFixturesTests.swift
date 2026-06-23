import Testing
@testable import SnapLedger

struct SampleDataFixturesTests {
    @Test func mayExpensesHasHeaderPlus37Rows() {
        let lines = SampleDataFixtures.expenses202605.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 38) // 헤더 1 + 지출 37건
        #expect(lines.first == "날짜,설명,카테고리,금액,메모")
    }

    @Test func juneExpensesHasHeaderPlus19Rows() {
        let lines = SampleDataFixtures.expenses202606.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 20) // 헤더 1 + 지출 19건
    }

    @Test func budgetLimitsCoverNineCategoriesWithoutEtc() {
        #expect(SampleDataFixtures.budgetLimits.count == 9)
        #expect(!SampleDataFixtures.budgetLimits.contains { $0.category == "기타" })
        #expect(SampleDataFixtures.budgetLimits.contains(BudgetSeed(category: "교통", monthlyLimit: 100_000)))
    }

    @Test func sampleMonthsAreMayAndJune2026() {
        #expect(SampleMonths.hero == 202605)
        #expect(SampleMonths.current == 202606)
    }
}
