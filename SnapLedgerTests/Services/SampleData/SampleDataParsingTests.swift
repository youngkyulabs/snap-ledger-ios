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
}
