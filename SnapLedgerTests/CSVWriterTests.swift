// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct CSVWriterTests {
    let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSVWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
        return utcCalendar.date(from: comps)!
    }

    @Test func writesBOMAndHeaderOnFirstCall() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(date: date(2026, 5, 17), description: "스타벅스",
                                   category: "카페", amount: 5000))

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let data = try Data(contentsOf: file)
        let utf8BOM = Data([0xEF, 0xBB, 0xBF])
        #expect(data.starts(with: utf8BOM))

        let content = String(data: data, encoding: .utf8) ?? ""
        let stripped = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        #expect(stripped.hasPrefix("날짜,설명,카테고리,금액\n"))
        #expect(stripped.contains("2026-05-17,스타벅스,카페,5000"))
    }

    @Test func appendDoesNotDuplicateHeader() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(date: date(2026, 5, 17), description: "A", amount: 100))
        try writer.append(SavedRow(date: date(2026, 5, 18), description: "B", amount: 200))

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let content = try String(contentsOf: file, encoding: .utf8)
        let headerCount = content.components(separatedBy: "날짜,설명,카테고리,금액").count - 1
        #expect(headerCount == 1)
        #expect(content.contains("2026-05-17,A,,100"))
        #expect(content.contains("2026-05-18,B,,200"))
    }

    @Test func escapesCommaQuoteAndNewline() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(date: date(2026, 5, 17),
                                   description: "Tom\"s, Cafe", amount: 1))
        try writer.append(SavedRow(date: date(2026, 5, 17),
                                   description: "line\nbreak", amount: 2))

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("\"Tom\"\"s, Cafe\""))
        #expect(content.contains("\"line\nbreak\""))
    }

    @Test func routesToMonthlyFiles() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append([
            SavedRow(date: date(2026, 4, 30), description: "Apr", amount: 1),
            SavedRow(date: date(2026, 5, 1), description: "May", amount: 2),
            SavedRow(date: date(2026, 5, 31), description: "May2", amount: 3),
        ])

        let aprContent = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-04.csv"),
            encoding: .utf8
        )
        let mayContent = try String(
            contentsOf: folder.appendingPathComponent("expenses-2026-05.csv"),
            encoding: .utf8
        )
        #expect(aprContent.contains("2026-04-30,Apr,,1"))
        #expect(mayContent.contains("2026-05-01,May,,2"))
        #expect(mayContent.contains("2026-05-31,May2,,3"))
    }

    @Test func nilCategoryRendersAsEmpty() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(date: date(2026, 5, 17), description: "A",
                                   category: nil, amount: 100))

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("2026-05-17,A,,100"))
    }

    @Test func escapesKoreanWithQuoteCommaAndNewline() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(
            date: date(2026, 5, 17),
            description: "이마트 \"스타벅스\", 강남\n2호점",
            category: "카페",
            amount: 7500
        ))

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("\"이마트 \"\"스타벅스\"\", 강남\n2호점\""))
        #expect(content.contains(",카페,7500"))
    }

    @Test func replaceMonthRewritesFromScratchWithHeader() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)

        try writer.append([
            SavedRow(date: date(2026, 5, 1), description: "A", amount: 100),
            SavedRow(date: date(2026, 5, 2), description: "B", amount: 200),
            SavedRow(date: date(2026, 5, 3), description: "C", amount: 300),
        ])

        try writer.replaceMonth(monthKey: "2026-05", rows: [
            SavedRow(date: date(2026, 5, 1), description: "A", amount: 100),
            SavedRow(date: date(2026, 5, 2), description: "B-수정", category: "식비", amount: 250),
        ])

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let data = try Data(contentsOf: file)
        let utf8BOM = Data([0xEF, 0xBB, 0xBF])
        #expect(data.starts(with: utf8BOM))

        let content = try String(contentsOf: file, encoding: .utf8)
        let headerCount = content.components(separatedBy: "날짜,설명,카테고리,금액").count - 1
        #expect(headerCount == 1)
        #expect(content.contains("2026-05-01,A,,100"))
        #expect(content.contains("2026-05-02,B-수정,식비,250"))
        #expect(!content.contains(",C,"))
        #expect(!content.contains(",300"))
    }

    @Test func replaceMonthWithEmptyRowsDeletesFile() throws {
        let folder = try makeTempFolder()
        let writer = CSVWriter(folder: folder, calendar: utcCalendar)
        try writer.append(SavedRow(date: date(2026, 5, 1), description: "A", amount: 100))

        try writer.replaceMonth(monthKey: "2026-05", rows: [])

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func monthKeyHelperFormatsAsYYYYDashMM() {
        #expect(CSVWriter.monthKey(for: date(2026, 1, 1), calendar: utcCalendar) == "2026-01")
        #expect(CSVWriter.monthKey(for: date(2026, 12, 31), calendar: utcCalendar) == "2026-12")
        #expect(CSVWriter.filename(forMonthKey: "2026-05") == "expenses-2026-05.csv")
    }

    @Test func multipleWriterInstancesPreserveHeaderUniqueness() throws {
        let folder = try makeTempFolder()
        let testDate = date(2026, 5, 17)

        for i in 0..<100 {
            let writer = CSVWriter(folder: folder, calendar: utcCalendar)
            try writer.append(SavedRow(
                date: testDate,
                description: "R\(i)",
                category: nil,
                amount: i
            ))
        }

        let file = folder.appendingPathComponent("expenses-2026-05.csv")
        let data = try Data(contentsOf: file)
        let utf8BOM = Data([0xEF, 0xBB, 0xBF])
        #expect(data.starts(with: utf8BOM))

        let content = try String(contentsOf: file, encoding: .utf8)
        let headerCount = content.components(separatedBy: "날짜,설명,카테고리,금액").count - 1
        #expect(headerCount == 1)

        let bomStripped = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        let lines = bomStripped.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 101)

        for i in 0..<100 {
            #expect(content.contains("R\(i)"))
        }
    }
}
