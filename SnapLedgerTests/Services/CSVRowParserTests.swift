import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct CSVRowParserTests {
    private func monthKey(_ date: Date) -> String {
        CSVWriter.monthKey(for: date)
    }

    @Test func parsesWellFormedCSVSkippingHeader() {
        let text = "\u{FEFF}날짜,설명,카테고리,금액,메모\n"
            + "2026-05-17,스타벅스,카페,5500,모닝\n"
            + "2026-05-18,김밥천국,식비,8000,\n"
        let result = CSVRowParser.parse(text)
        #expect(result.skipped == 0)
        #expect(result.rows.count == 2)

        let first = result.rows[0]
        #expect(first.description == "스타벅스")
        #expect(first.category == "카페")
        #expect(first.amount == 5500)
        #expect(first.note == "모닝")
        #expect(monthKey(first.date) == "2026-05")

        let second = result.rows[1]
        #expect(second.category == "식비")
        #expect(second.note == nil) // 빈 메모 → nil
    }

    @Test func countsRowsWithBadDateOrAmount() {
        let text = "날짜,설명,카테고리,금액,메모\n"
            + "NOTADATE,A,,100,\n"
            + "2026-05-01,B,,NOTNUM,\n"
            + "2026-05-02,C,,300,\n"
        let result = CSVRowParser.parse(text)
        #expect(result.rows.count == 1)
        #expect(result.skipped == 2)
        #expect(result.rows[0].description == "C")
    }

    @Test func handlesFourColumnRowsWithoutNote() {
        let text = "날짜,설명,카테고리,금액\n2026-05-02,C,식비,300\n"
        let result = CSVRowParser.parse(text)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].note == nil)
        #expect(result.rows[0].amount == 300)
    }

    @Test func stripsThousandsSeparatorInAmount() {
        let text = "날짜,설명,카테고리,금액,메모\n2026-05-02,C,,\"12,000\",\n"
        let result = CSVRowParser.parse(text)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].amount == 12000)
    }

    @Test func ignoresBlankLines() {
        let text = "날짜,설명,카테고리,금액,메모\n\n2026-05-02,C,,300,\n\n"
        let result = CSVRowParser.parse(text)
        #expect(result.rows.count == 1)
    }

    @Test func emptyInputYieldsNoRows() {
        let result = CSVRowParser.parse("")
        #expect(result.rows.isEmpty)
        #expect(result.skipped == 0)
    }

    @Test func parsesEvenWithoutHeaderRow() {
        // 헤더 없이 데이터만 있는 파일도 허용 (첫 행이 헤더가 아니면 그대로 데이터)
        let text = "2026-05-02,C,,300,\n2026-05-03,D,,400,\n"
        let result = CSVRowParser.parse(text)
        #expect(result.rows.count == 2)
        #expect(result.skipped == 0)
    }
}
