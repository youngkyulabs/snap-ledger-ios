import Foundation
import Testing
@testable import SnapLedger

struct SampleDataFixturesTests {
    @Test func mayExpensesHasHeaderPlus37Rows() {
        let lines = SampleDataFixtures.expensesHero.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 38) // 1 header + 37 expense rows
        #expect(lines.first == "날짜,설명,카테고리,금액,메모")
    }

    @Test func juneExpensesHasHeaderPlus19Rows() {
        let lines = SampleDataFixtures.expensesCurrent.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 20) // 1 header + 19 expense rows
    }

    @Test func budgetLimitsCoverNineCategoriesWithoutEtc() {
        #expect(SampleDataFixtures.budgetLimits.count == 9)
        #expect(!SampleDataFixtures.budgetLimits.contains { $0.category == "기타" })
        #expect(SampleDataFixtures.budgetLimits.contains(BudgetSeed(category: "교통", monthlyLimit: 100_000)))
    }

    @Test func sampleMonthsTrackTodayAndPreviousMonth() {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        #expect(SampleMonths.current == (comps.year ?? 0) * 100 + (comps.month ?? 0))

        let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let prevComps = calendar.dateComponents([.year, .month], from: previous)
        #expect(SampleMonths.hero == (prevComps.year ?? 0) * 100 + (prevComps.month ?? 0))
    }

    @Test func monthKeyRollsOverToPreviousYearInJanuary() {
        let january = SampleDataParsing.parseDate("2026-01-15") ?? Date()
        #expect(SampleMonths.key(monthsFromNow: 0, now: january) == 202601)
        #expect(SampleMonths.key(monthsFromNow: -1, now: january) == 202512)
    }

    @Test func reviewSeedsStayWithinYesterdaySoNoDateWarningShows() {
        #expect(SampleDataFixtures.reviewSeeds.allSatisfy { (0...1).contains($0.daysAgo) })
        let now = Date()
        for seed in SampleDataFixtures.reviewSeeds {
            let date = SampleDataParsing.noon(daysAgo: seed.daysAgo, now: now)
            #expect(!ReviewDateCheck.status(for: date, now: now).isWarning)
        }
    }
}
