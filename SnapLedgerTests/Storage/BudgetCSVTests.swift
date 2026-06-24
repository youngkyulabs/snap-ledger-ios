import Foundation
import Testing
@testable import SnapLedger

struct BudgetCSVTests {
    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetCSVTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func filenameUsesBudgetsPrefix() {
        #expect(BudgetCSVWriter.filename(forMonthKey: "2026-06") == "budgets-2026-06.csv")
    }

    @Test func writesBOMHeaderAndEscapedRows() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = BudgetCSVWriter(folder: folder)
        try writer.replaceMonth(monthKey: "2026-06", rows: [
            BudgetCSVRow(category: "식비", limit: 300_000),
            BudgetCSVRow(category: "교통, \"버스\"", limit: 80_000),
        ])

        let file = folder.appendingPathComponent("budgets-2026-06.csv")
        let data = try Data(contentsOf: file)
        #expect(data.starts(with: Data([0xEF, 0xBB, 0xBF])))

        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("카테고리,한도"))
        #expect(content.contains("식비,300000"))
        #expect(content.contains("\"교통, \"\"버스\"\"\",80000"))
    }

    @Test func emptyRowsRemovesExistingFile() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = BudgetCSVWriter(folder: folder)
        try writer.replaceMonth(monthKey: "2026-06", rows: [BudgetCSVRow(category: "식비", limit: 1)])
        let file = folder.appendingPathComponent("budgets-2026-06.csv")
        #expect(FileManager.default.fileExists(atPath: file.path))

        try writer.replaceMonth(monthKey: "2026-06", rows: [])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
