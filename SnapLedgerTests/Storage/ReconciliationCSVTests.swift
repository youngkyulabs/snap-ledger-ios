// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

struct ReconciliationCSVTests {
    let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconciliationCSVTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return utcCalendar.date(from: comps)!
    }

    @Test func filenameUsesReconciliationsPrefix() {
        #expect(ReconciliationCSVWriter.filename(forMonthKey: "2026-06") == "reconciliations-2026-06.csv")
        #expect(ReconciliationCSVWriter.monthKey(fromFilename: "reconciliations-2026-06.csv") == "2026-06")
        #expect(ReconciliationCSVWriter.monthKey(fromFilename: "settlements-2026-06.csv") == nil)
    }

    @Test func writesBOMHeaderAndEscapedRows() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = ReconciliationCSVWriter(folder: folder, calendar: utcCalendar)
        try writer.replaceMonth(monthKey: "2026-06", rows: [
            ReconciliationCSVRow(kind: .salary, date: nil, account: nil, title: "월급", direction: nil, amount: 3_000_000),
            ReconciliationCSVRow(kind: .openingBalance, date: nil, account: "입출금", title: nil, direction: nil, amount: 1_000_000),
            ReconciliationCSVRow(
                kind: .cashAdjustment,
                date: date(2026, 6, 10),
                account: nil,
                title: "환급, \"교통비\"",
                direction: .deposit,
                amount: 12_000,
                note: "줄1\n줄2"
            ),
        ])

        let file = folder.appendingPathComponent("reconciliations-2026-06.csv")
        let data = try Data(contentsOf: file)
        #expect(data.starts(with: Data([0xEF, 0xBB, 0xBF])))

        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("종류,날짜,계좌,항목,방향,금액,메모"))
        #expect(content.contains("월급,,,월급,,3000000,"))
        #expect(content.contains("기초잔액,,입출금,,,1000000,"))
        #expect(content.contains("자금변동,2026-06-10,,\"환급, \"\"교통비\"\"\",입금,12000,\"줄1\n줄2\""))
    }

    @Test func parsesWrittenRowsRoundTrip() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let rows = [
            ReconciliationCSVRow(kind: .salary, date: nil, account: nil, title: "월급", direction: nil, amount: 3_000_000),
            ReconciliationCSVRow(kind: .creditCard, date: nil, account: nil, title: "카드", direction: nil, amount: 450_000),
            ReconciliationCSVRow(kind: .savings, date: nil, account: nil, title: "적금", direction: nil, amount: 300_000),
            ReconciliationCSVRow(kind: .savings, date: nil, account: nil, title: "펀드", direction: nil, amount: 200_000),
            ReconciliationCSVRow(kind: .interest, date: nil, account: "적금", title: nil, direction: nil, amount: 10_000),
            ReconciliationCSVRow(
                kind: .cashAdjustment,
                date: date(2026, 6, 25),
                account: nil,
                title: "전월 카드대금",
                direction: .withdrawal,
                amount: 400_000,
                note: "5월분"
            ),
        ]

        let writer = ReconciliationCSVWriter(folder: folder, calendar: utcCalendar)
        try writer.replaceMonth(monthKey: "2026-06", rows: rows)

        let content = try String(
            contentsOf: folder.appendingPathComponent("reconciliations-2026-06.csv"),
            encoding: .utf8
        )
        let parsed = ReconciliationCSVParser.parse(content, calendar: utcCalendar)

        #expect(parsed.rows == rows)
        #expect(parsed.skipped == 0)
    }

    @Test func parserSkipsInvalidRowsWithoutDroppingValidRows() {
        let csv = """
        종류,날짜,계좌,항목,방향,금액,메모
        월급,,,,,3000000,
        이상한종류,,,,,100,
        자금변동,2026-06-10,,환급,입금,12000,
        자금변동,not-date,,오류,입금,100,
        저축액,,,,,bad,
        """

        let parsed = ReconciliationCSVParser.parse(csv, calendar: utcCalendar)

        #expect(parsed.rows.count == 2)
        #expect(parsed.rows.map(\.kind) == [.salary, .cashAdjustment])
        #expect(parsed.skipped == 3)
    }
}
