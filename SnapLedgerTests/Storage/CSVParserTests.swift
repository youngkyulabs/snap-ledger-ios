import Foundation
import Testing
@testable import SnapLedger

struct CSVParserTests {
    @Test func parsesSimpleRows() {
        let csv = "날짜,설명,카테고리,금액\n2026-05-17,스타벅스,카페,5000\n"
        let rows = CSVParser.parse(csv)
        #expect(rows.count == 2)
        #expect(rows[0] == ["날짜", "설명", "카테고리", "금액"])
        #expect(rows[1] == ["2026-05-17", "스타벅스", "카페", "5000"])
    }

    @Test func stripsLeadingBOM() {
        let csv = "\u{FEFF}날짜,설명\n2026-05-17,A\n"
        let rows = CSVParser.parse(csv)
        #expect(rows[0] == ["날짜", "설명"])
    }

    @Test func handlesEmptyCategoryField() {
        let csv = "날짜,설명,카테고리,금액\n2026-05-17,A,,100\n"
        let rows = CSVParser.parse(csv)
        #expect(rows[1] == ["2026-05-17", "A", "", "100"])
    }

    @Test func unquotesDoubleQuotedFields() {
        let csv = "a,b\n\"hello\",\"world\"\n"
        let rows = CSVParser.parse(csv)
        #expect(rows[1] == ["hello", "world"])
    }

    @Test func unescapesEmbeddedQuotes() {
        let csv = "a,b\n\"Tom\"\"s Cafe\",X\n"
        let rows = CSVParser.parse(csv)
        #expect(rows[1] == ["Tom\"s Cafe", "X"])
    }

    @Test func preservesCommaInsideQuotedField() {
        let csv = "a,b\n\"hello, world\",X\n"
        let rows = CSVParser.parse(csv)
        #expect(rows[1] == ["hello, world", "X"])
    }

    @Test func preservesNewlineInsideQuotedField() {
        let csv = "a,b\n\"line\nbreak\",X\n"
        let rows = CSVParser.parse(csv)
        #expect(rows.count == 2)
        #expect(rows[1] == ["line\nbreak", "X"])
    }

    @Test func roundTripsRowsWrittenByCSVWriter() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSVParserRT-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let writer = CSVWriter(folder: folder, calendar: utc)
        var comps = DateComponents(); comps.year = 2026; comps.month = 5; comps.day = 17
        let date = utc.date(from: comps) ?? Date()
        try writer.append([
            SavedRow(date: date, description: "Tom\"s, Cafe", category: "카페", amount: 5000),
            SavedRow(date: date, description: "line\nbreak", category: nil, amount: 200),
        ])

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let content = try String(contentsOf: file, encoding: .utf8)
        let rows = CSVParser.parse(content)

        #expect(rows.count == 3)
        #expect(rows[0] == ["날짜", "설명", "카테고리", "금액"])
        #expect(rows[1] == ["2026-05-17", "Tom\"s, Cafe", "카페", "5000"])
        #expect(rows[2] == ["2026-05-17", "line\nbreak", "", "200"])
    }

    @Test func emptyInputReturnsEmptyArray() {
        #expect(CSVParser.parse("").isEmpty)
        #expect(CSVParser.parse("\u{FEFF}").isEmpty)
    }
}
