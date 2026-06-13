// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct BudgetProgressTests {
    let kst: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        cal.locale = Locale(identifier: "ko_KR")
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        comps.timeZone = TimeZone(identifier: "Asia/Seoul")
        return kst.date(from: comps)!
    }

    private func entry(_ y: Int, _ m: Int, _ d: Int, amount: Int, category: String?) -> SavedEntry {
        SavedEntry(date: date(y, m, d), amount: amount, merchant: "M", category: category,
                   savedAt: date(y, m, d), csvFile: "expenses-\(y)-\(String(format: "%02d", m)).csv")
    }

    @Test func usagePercentStaysBelow100UntilOver() {
        // 한도를 넘기 전(ratio < 1)에는 99.5~99.99%가 100%로 반올림돼선 안 된다
        // ("100% · N원 남음" 모순 표기 방지).
        #expect(BudgetProgress.usagePercent(ratio: 0.999) == 99)
        #expect(BudgetProgress.usagePercent(ratio: 0.995) == 99)
        #expect(BudgetProgress.usagePercent(ratio: 0.8) == 80)
        // 한도 도달·초과는 그대로 100% 이상으로 보여준다.
        #expect(BudgetProgress.usagePercent(ratio: 1.0) == 100)
        #expect(BudgetProgress.usagePercent(ratio: 1.5) == 150)
    }

    @Test func emptyInputsAreSafe() {
        let s = BudgetProgress.compute(entries: [], budgets: [], targetMonth: 202_606, calendar: kst)
        #expect(s.totalSpent == 0)
        #expect(s.totalLimit == 0)
        #expect(s.lines.isEmpty)
        #expect(s.unbudgeted.isEmpty)
        #expect(s.overallState == .under)
    }

    @Test func budgetedLineComputesSpentLimitRemainingRatio() {
        let entries = [entry(2026, 6, 1, amount: 120_000, category: "식비")]
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 150_000, effectiveFrom: 202_606)]
        let s = BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_606, calendar: kst)
        #expect(s.lines.count == 1)
        let line = s.lines[0]
        #expect(line.spent == 120_000)
        #expect(line.limit == 150_000)
        #expect(line.remaining == 30_000)
        #expect(abs(line.ratio - 0.8) < 0.0001)
        #expect(line.state == .near)
    }

    @Test func stateBoundaries() {
        func state(spent: Int, limit: Int) -> BudgetProgress.State {
            let entries = [entry(2026, 6, 1, amount: spent, category: "식비")]
            let budgets = [CategoryBudget(category: "식비", monthlyLimit: limit, effectiveFrom: 202_606)]
            return BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_606, calendar: kst).lines[0].state
        }
        #expect(state(spent: 79, limit: 100) == .under)
        #expect(state(spent: 80, limit: 100) == .near)
        #expect(state(spent: 99, limit: 100) == .near)
        #expect(state(spent: 100, limit: 100) == .over)
        #expect(state(spent: 150, limit: 100) == .over)
    }

    @Test func totalSpentIncludesUnbudgetedAndUncategorized() {
        let entries = [
            entry(2026, 6, 1, amount: 100_000, category: "식비"),
            entry(2026, 6, 2, amount: 40_000, category: "쇼핑"),
            entry(2026, 6, 3, amount: 10_000, category: nil),
        ]
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 150_000, effectiveFrom: 202_606)]
        let s = BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_606, calendar: kst)
        #expect(s.totalSpent == 150_000)
        #expect(s.totalLimit == 150_000)
        #expect(s.budgetedSpent == 100_000)
        #expect(s.unbudgetedSpent == 50_000)
        #expect(Set(s.unbudgeted.map(\.category)) == ["쇼핑", "미분류"])
    }

    @Test func linesSortedByRatioDescending() {
        let entries = [
            entry(2026, 6, 1, amount: 90_000, category: "식비"),
            entry(2026, 6, 2, amount: 30_000, category: "카페"),
        ]
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 100_000, effectiveFrom: 202_606),
            CategoryBudget(category: "카페", monthlyLimit: 50_000, effectiveFrom: 202_606),
        ]
        let s = BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_606, calendar: kst)
        #expect(s.lines.map(\.category) == ["식비", "카페"])
    }

    @Test func budgetedCategoryWithZeroSpendingStillShown() {
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 100_000, effectiveFrom: 202_606)]
        let s = BudgetProgress.compute(entries: [], budgets: budgets, targetMonth: 202_606, calendar: kst)
        #expect(s.lines.count == 1)
        #expect(s.lines[0].spent == 0)
        #expect(s.lines[0].state == .under)
    }

    @Test func otherMonthsExcluded() {
        let entries = [
            entry(2026, 5, 1, amount: 50_000, category: "식비"),
            entry(2026, 6, 1, amount: 20_000, category: "식비"),
        ]
        let budgets = [CategoryBudget(category: "식비", monthlyLimit: 100_000, effectiveFrom: 202_601)]
        let s = BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_606, calendar: kst)
        #expect(s.lines[0].spent == 20_000)
    }

    @Test func deletedCategoryStillBudgetedLineInPastMonth() {
        let entries = [entry(2026, 3, 10, amount: 250_000, category: "식비")]
        let budgets = [
            CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_601),
            CategoryBudget(category: "식비", monthlyLimit: 0, effectiveFrom: 202_606),
        ]
        let march = BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: 202_603, calendar: kst)
        #expect(march.lines.count == 1)
        #expect(march.lines[0].category == "식비")
        #expect(march.lines[0].limit == 300_000)
        #expect(march.lines[0].spent == 250_000)

        let june = BudgetProgress.compute(
            entries: [entry(2026, 6, 10, amount: 100_000, category: "식비")],
            budgets: budgets, targetMonth: 202_606, calendar: kst
        )
        #expect(june.lines.isEmpty)
        #expect(june.unbudgeted.map(\.category) == ["식비"])
    }
}
