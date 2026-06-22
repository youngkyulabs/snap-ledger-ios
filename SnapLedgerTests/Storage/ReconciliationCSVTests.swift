import Foundation
import Testing
@testable import SnapLedger

struct ReconciliationCSVTests {
    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconciliationCSVTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func filenameUsesReconciliationsPrefix() {
        #expect(ReconciliationCSVWriter.filename(forMonthKey: "2026-06") == "reconciliations-2026-06.csv")
    }

    @Test func writesBOMHeaderAndEscapedRows() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = ReconciliationCSVWriter(folder: folder)
        try writer.replaceMonth(monthKey: "2026-06", rows: [
            ReconciliationCSVRow(kind: .income, title: "월급", amount: 3_000_000),
            ReconciliationCSVRow(kind: .openingBalance, account: "입출금", amount: 1_000_000),
            ReconciliationCSVRow(
                kind: .cashAdjustment,
                title: "환급, \"교통비\"",
                direction: .deposit,
                amount: 12_000,
                note: "줄1\n줄2"
            ),
            ReconciliationCSVRow(kind: .monthNote, note: "보너스 포함"),
        ])

        let file = folder.appendingPathComponent("reconciliations-2026-06.csv")
        let data = try Data(contentsOf: file)
        #expect(data.starts(with: Data([0xEF, 0xBB, 0xBF])))

        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(content.contains("종류,항목,계좌,방향,금액,메모"))
        #expect(content.contains("수입,월급,,,3000000,"))
        #expect(content.contains("기초잔액,,입출금,,1000000,"))
        #expect(content.contains("자금변동,\"환급, \"\"교통비\"\"\",,입금,12000,\"줄1\n줄2\""))
        #expect(content.contains("월메모,,,,,보너스 포함"))
    }

    @Test func parsesWrittenRowsRoundTrip() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let rows = [
            ReconciliationCSVRow(kind: .income, title: "월급", amount: 3_000_000),
            ReconciliationCSVRow(kind: .creditCard, title: "카드", amount: 450_000),
            ReconciliationCSVRow(kind: .savings, title: "적금", amount: 300_000),
            ReconciliationCSVRow(kind: .savings, title: "펀드", amount: 200_000),
            ReconciliationCSVRow(kind: .interest, account: "적금", amount: 10_000),
            ReconciliationCSVRow(
                kind: .cashAdjustment,
                title: "전월 카드대금",
                direction: .withdrawal,
                amount: 400_000,
                note: "5월분"
            ),
            ReconciliationCSVRow(kind: .monthNote, note: "이번 달 메모"),
        ]

        let writer = ReconciliationCSVWriter(folder: folder)
        try writer.replaceMonth(monthKey: "2026-06", rows: rows)

        let content = try String(
            contentsOf: folder.appendingPathComponent("reconciliations-2026-06.csv"),
            encoding: .utf8
        )
        let parsed = ReconciliationCSVParser.parse(content)

        #expect(parsed.rows == rows)
        #expect(parsed.skipped == 0)
    }

    @Test func parserAcceptsThousandsSeparatorInAmount() {
        // 외부 편집기·스프레드시트가 금액을 천 단위 구분자로 다시 쓴 파일도 받아들인다
        // (지출 CSV 파서와 동일). 따옴표로 감싼 "3,000,000"은 한 필드로 들어온다.
        let csv = """
        종류,항목,계좌,방향,금액,메모
        수입,월급,,,"3,000,000",
        카드사용액,주카드,,,"450,000",
        """

        let parsed = ReconciliationCSVParser.parse(csv)

        #expect(parsed.skipped == 0)
        #expect(parsed.rows.count == 2)
        #expect(parsed.rows.first?.amount == 3_000_000)
        #expect(parsed.rows.last?.amount == 450_000)
    }

    @Test func parserSkipsInvalidRows() {
        let csv = """
        종류,항목,계좌,방향,금액,메모
        수입,월급,,,3000000,
        이상한종류,,,,100,
        자금변동,환급,,입금,12000,
        자금변동,방향없음,,,100,
        저축액,펀드,,,bad,
        기초잔액,,,,1000,
        월메모,,,,,달 메모
        """

        let parsed = ReconciliationCSVParser.parse(csv)

        #expect(parsed.rows.map(\.kind) == [.income, .cashAdjustment, .monthNote])
        #expect(parsed.skipped == 4)
    }
}
