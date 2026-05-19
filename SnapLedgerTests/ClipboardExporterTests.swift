// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ClipboardExporterTests {
    let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
        return utcCalendar.date(from: comps)!
    }

    @Test func singleRowTSV() {
        let row = SavedRow(date: date(2026, 5, 17), description: "스타벅스",
                           category: "카페", amount: 5000)
        let tsv = ClipboardExporter.tsv(for: [row], calendar: utcCalendar)
        #expect(tsv == "2026-05-17\t스타벅스\t카페\t5000")
    }

    @Test func multipleRowsJoinedByLF() {
        let rows = [
            SavedRow(date: date(2026, 5, 17), description: "A", category: "카페", amount: 1),
            SavedRow(date: date(2026, 5, 18), description: "B", category: "교통", amount: 2),
        ]
        let tsv = ClipboardExporter.tsv(for: rows, calendar: utcCalendar)
        #expect(tsv == "2026-05-17\tA\t카페\t1\n2026-05-18\tB\t교통\t2")
    }

    @Test func nilCategoryRendersAsEmpty() {
        let row = SavedRow(date: date(2026, 5, 17), description: "A",
                           category: nil, amount: 100)
        let tsv = ClipboardExporter.tsv(for: [row], calendar: utcCalendar)
        #expect(tsv == "2026-05-17\tA\t\t100")
    }

    @Test func sanitizesTabAndNewlineInFields() {
        let row = SavedRow(date: date(2026, 5, 17),
                           description: "line\nbreak\there",
                           category: "k\ta", amount: 1)
        let tsv = ClipboardExporter.tsv(for: [row], calendar: utcCalendar)
        #expect(tsv == "2026-05-17\tline break here\tk a\t1")
    }

    @Test func emptyRowsReturnsEmptyString() {
        let tsv = ClipboardExporter.tsv(for: [], calendar: utcCalendar)
        #expect(tsv.isEmpty)
    }

    @Test func stringRowsJoinedWithTabsAndLF() {
        let tsv = ClipboardExporter.tsv(rows: [
            ["날짜", "설명", "카테고리", "금액"],
            ["2026-05-17", "스타벅스", "카페", "5000"],
            ["2026-05-18", "GS25", "", "3000"],
        ])
        let expected = """
        날짜\t설명\t카테고리\t금액
        2026-05-17\t스타벅스\t카페\t5000
        2026-05-18\tGS25\t\t3000
        """
        #expect(tsv == expected)
    }

    @Test func stringRowsSanitizeTabsAndNewlinesWithinCells() {
        let tsv = ClipboardExporter.tsv(rows: [
            ["a", "line\nbreak", "x\ty"],
        ])
        #expect(tsv == "a\tline break\tx y")
    }

    @Test func emptyStringRowsReturnsEmpty() {
        #expect(ClipboardExporter.tsv(rows: []).isEmpty)
    }

    @Test func htmlWithHeaderUsesTheadAndTbody() {
        let html = ClipboardExporter.html(rows: [
            ["날짜", "설명", "금액"],
            ["2026-05-17", "스타벅스", "5000"],
        ], hasHeader: true)

        #expect(html.hasPrefix("<table>"))
        #expect(html.hasSuffix("</table>"))
        #expect(html.contains("<thead><tr><th>날짜</th><th>설명</th><th>금액</th></tr></thead>"))
        #expect(html.contains("<tbody><tr><td>2026-05-17</td><td>스타벅스</td><td>5000</td></tr></tbody>"))
    }

    @Test func htmlWithoutHeaderPutsEverythingInTbody() {
        let html = ClipboardExporter.html(rows: [
            ["2026-05-17", "A", "100"],
        ], hasHeader: false)

        #expect(html == "<table><tbody><tr><td>2026-05-17</td><td>A</td><td>100</td></tr></tbody></table>")
    }

    @Test func htmlEscapesEntitiesAndConvertsNewlinesToBR() {
        let html = ClipboardExporter.html(rows: [
            ["a&b<c>", "\"hi\"", "line\nbreak"],
        ], hasHeader: false)

        #expect(html.contains("<td>a&amp;b&lt;c&gt;</td>"))
        #expect(html.contains("<td>&quot;hi&quot;</td>"))
        #expect(html.contains("<td>line<br>break</td>"))
    }

    @Test func htmlEmptyRowsReturnsEmpty() {
        #expect(ClipboardExporter.html(rows: [], hasHeader: true).isEmpty)
        #expect(ClipboardExporter.html(rows: [], hasHeader: false).isEmpty)
    }
}
