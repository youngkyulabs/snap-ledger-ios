import Foundation
import Testing
@testable import SnapLedger

struct SampleDataParsingTests {
    @Test func parsesMayExpensesCountAndTotal() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
        #expect(seeds.count == 37)
        #expect(seeds.reduce(0) { $0 + $1.amount } == 876_500)
    }

    @Test func mayCategoryTotalsMatchReadme() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
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
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
        let first = seeds[0]
        #expect(first.merchant == "스타벅스 강남R점")
        #expect(first.category == "카페")
        #expect(first.amount == 5_800)
        #expect(first.note == "아메리카노+크루아상")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let comps = cal.dateComponents([.year, .month, .day], from: first.date)
        #expect(comps.year == 2026 && comps.month == 5 && comps.day == 1)
    }

    @Test func emptyNoteBecomesNil() {
        let seeds = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
        // 2번째 행(GS25 역삼점)은 메모가 빈 칸.
        #expect(seeds[1].merchant == "GS25 역삼점")
        #expect(seeds[1].note == nil)
    }

    @Test func mayReconciliationMapsBalancesByNickname() {
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliation202605)
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
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliation202605)
        #expect(draft.incomes.map(\.title) == ["월급", "부수입"])
        #expect(draft.cards.map(\.amount) == [480_000, 200_000])
        #expect(draft.savings.map(\.amount) == [100_000, 300_000])
        #expect(draft.adjustments.contains { $0.title == "경조사비" && $0.direction == .withdrawal && $0.amount == 150_000 })
        #expect(draft.adjustments.contains { $0.title == "용돈" && $0.direction == .deposit && $0.amount == 50_000 })
        #expect(draft.note.contains("교통비가 예산을 넘김"))
    }

    @Test func mayReconciliationReconcilesToZeroDifference() {
        let expenses = SampleDataParsing.parseExpenses(SampleDataFixtures.expenses202605)
        let entries = expenses.map {
            SavedEntry(date: $0.date, amount: $0.amount, merchant: $0.merchant,
                       category: $0.category, note: $0.note, csvFile: "expenses-2026-05.csv")
        }
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliation202605)
        let summary = draft.summary(entries: entries, month: SampleMonths.hero)
        #expect(summary.recordedSpending == 876_500)
        #expect(summary.actualSpending == 876_500)
        #expect(summary.difference == 0)
        #expect(summary.isBalanced)
        // 마감된 5월은 정산 데이터가 있으므로 확정 → "정상·차이 없음".
        #expect(summary.isReconciled(status: .closed))
    }

    @Test func juneReconciliationClosingDefaultsToOpening() {
        let draft = SampleDataParsing.parseReconciliationDraft(SampleDataFixtures.reconciliation202606)
        for balance in draft.balances {
            #expect(balance.closing == balance.opening) // 기말잔액 행 없음 → 중립
        }
    }
}
