import Foundation
import Testing
@testable import SnapLedger

struct SampleDataParsingTests {
    @Test func parsesMayExpensesCountAndTotal() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        #expect(seeds.count == 37)
        #expect(seeds.reduce(0) { $0 + $1.amount } == 876_500)
    }

    @Test func mayCategoryTotalsMatchReadme() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        func total(_ category: String) -> Int {
            seeds.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
        }
        #expect(total("교통") == 109_100)
        #expect(total("구독") == 28_400)
        #expect(total("공과금") == 93_600)
        #expect(total("식비") == 180_200)
        #expect(total("문화") == 60_300)
        #expect(total("쇼핑") == 196_500)
        #expect(total("카페") == 43_300)
        #expect(total("생활") == 141_700)
        #expect(total("의료") == 23_400)
    }

    @Test func parsesDateAndFields() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        let first = seeds[0]
        #expect(first.merchant == "스타벅스 강남R점")
        #expect(first.category == "카페")
        #expect(first.amount == 5_800)
        #expect(first.note == "아메리카노+크루아상")
        // Seed dates created at noon in current calendar.
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: first.date)
        #expect(comps.year == 2026 && comps.month == 5 && comps.day == 1)
    }

    @Test func emptyNoteBecomesNil() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        // Second row has empty note
        #expect(seeds[1].merchant == "GS25 역삼점")
        #expect(seeds[1].note == nil)
    }

    @Test func mayReconciliationMapsBalancesByNickname() {
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliationHero)
        #expect(draft.balances.count == 2)
        #expect(draft.balances[0].accountName == "월급통장")
        #expect(draft.balances[1].accountName == "비상금")
        #expect(draft.balances[0].sortOrder == 0)
        #expect(draft.balances[1].sortOrder == 1)
        let payroll = draft.balances.first { $0.accountName == "월급통장" }
        #expect(payroll?.opening == 1_250_000)
        #expect(payroll?.closing == 3_733_500)
        let emergency = draft.balances.first { $0.accountName == "비상금" }
        #expect(emergency?.opening == 5_000_000)
        #expect(emergency?.closing == 5_012_000)
        #expect(emergency?.interest == 12_000)
    }

    @Test func mayReconciliationMapsLineItemsAndAdjustments() {
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliationHero)
        #expect(draft.incomes.map(\.title) == ["월급", "부수입"])
        #expect(draft.cards.map(\.amount) == [480_000, 200_000])
        #expect(draft.savings.map(\.amount) == [100_000, 300_000])
        #expect(draft.adjustments.contains { $0.title == "경조사비" && $0.direction == .withdrawal && $0.amount == 150_000 })
        #expect(draft.adjustments.contains { $0.title == "용돈" && $0.direction == .deposit && $0.amount == 50_000 })
        #expect(draft.note.contains("교통비가 예산을 넘김"))
    }

    @Test func heroReconciliationReconcilesToZeroDifference() {
        let month = SampleMonths.hero
        let expenses = SampleDataParsing.remapSeeds(
            SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero),
            to: month
        )
        let entries = expenses.map {
            SavedEntry(date: $0.date, amount: $0.amount, merchant: $0.merchant,
                       category: $0.category, note: $0.note,
                       csvFile: CSVWriter.filename(forMonthKey: ReconciliationStore.monthString(from: month)))
        }
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliationHero)
        let summary = draft.summary(entries: entries, month: month)
        #expect(summary.recordedSpending == 876_500)
        #expect(summary.actualSpending == 876_500)
        #expect(summary.difference == 0)
        #expect(summary.isBalanced)
        // Closed month with reconciliation data -> balanced
        #expect(summary.isReconciled(status: .closed))
    }

    @Test func remapMovesSeedsOntoTargetMonthKeepingDayOfMonth() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        let remapped = SampleDataParsing.remapSeeds(seeds, to: 202_401)
        #expect(remapped.count == seeds.count)
        let calendar = Calendar.current
        for (original, moved) in zip(seeds, remapped) {
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: moved.date)
            #expect(comps.year == 2024 && comps.month == 1)
            #expect(comps.day == calendar.component(.day, from: original.date))
            #expect(comps.hour == 12)
            #expect(moved.amount == original.amount)
            #expect(moved.merchant == original.merchant)
        }
    }

    @Test func remapClampsDayToShorterMonth() {
        // May 31 has no counterpart in February
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expensesHero)
        let remapped = SampleDataParsing.remapSeeds(seeds, to: 202_302)
        let days = remapped.map { Calendar.current.component(.day, from: $0.date) }
        #expect(days.allSatisfy { $0 <= 28 })
        #expect(days.contains(28))
    }

    @Test func droppingFutureKeepsTodayAndDropsTomorrow() {
        let calendar = Calendar.current
        let now = Date()
        func seed(daysFromNow: Int) -> ExpenseSeed {
            ExpenseSeed(date: SampleDataParsing.noon(daysAgo: -daysFromNow, now: now),
                        merchant: "가맹점", category: "식비", amount: 1_000, note: nil)
        }
        let kept = SampleDataParsing.droppingFuture(
            [seed(daysFromNow: -1), seed(daysFromNow: 0), seed(daysFromNow: 1)],
            now: now
        )
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: now) })
    }

    @Test func noonReturnsMiddayOfRequestedDay() {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = SampleDataParsing.noon(daysAgo: 1, now: now)
        let comps = calendar.dateComponents([.hour, .minute, .second], from: yesterday)
        #expect(comps.hour == 12 && comps.minute == 0 && comps.second == 0)
        let expectedDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        #expect(calendar.startOfDay(for: yesterday) == expectedDay)
    }

    @Test func currentMonthReconciliationClosingDefaultsToOpening() {
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliationCurrent)
        for balance in draft.balances {
            #expect(balance.closing == balance.opening) // Default closing to opening balance
        }
    }
}
