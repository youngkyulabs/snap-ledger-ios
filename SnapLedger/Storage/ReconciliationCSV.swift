import Foundation

enum ReconciliationCSVKind: String, CaseIterable, Sendable {
    case income = "수입"
    case creditCard = "카드사용액"
    case savings = "저축액"
    case openingBalance = "기초잔액"
    case closingBalance = "기말잔액"
    case interest = "이자"
    case cashAdjustment = "자금변동"
    case monthNote = "월메모"
}

struct ReconciliationCSVRow: Equatable, Sendable {
    let kind: ReconciliationCSVKind
    let account: String?
    let title: String?
    let direction: CashAdjustmentDirection?
    let amount: Int?
    let note: String?

    init(
        kind: ReconciliationCSVKind,
        account: String? = nil,
        title: String? = nil,
        direction: CashAdjustmentDirection? = nil,
        amount: Int? = nil,
        note: String? = nil
    ) {
        self.kind = kind
        self.account = account
        self.title = title
        self.direction = direction
        self.amount = amount
        self.note = note
    }
}

struct ReconciliationCSVParseResult: Equatable {
    let rows: [ReconciliationCSVRow]
    let skipped: Int
}

struct ReconciliationCSVParser {
    static func parse(_ content: String) -> ReconciliationCSVParseResult {
        let rawRows = CSVParser.parse(content)
        guard !rawRows.isEmpty else {
            return ReconciliationCSVParseResult(rows: [], skipped: 0)
        }

        var rows: [ReconciliationCSVRow] = []
        var skipped = 0
        for raw in rawRows.dropFirst() {
            guard let row = parseRow(raw) else {
                skipped += 1
                continue
            }
            rows.append(row)
        }
        return ReconciliationCSVParseResult(rows: rows, skipped: skipped)
    }

    private static func parseRow(_ raw: [String]) -> ReconciliationCSVRow? {
        guard let kind = ReconciliationCSVKind(rawValue: raw[safe: 0] ?? "") else {
            return nil
        }
        let title = nonEmpty(raw[safe: 1])
        let account = nonEmpty(raw[safe: 2])
        let direction = nonEmpty(raw[safe: 3]).flatMap(CashAdjustmentDirection.from(label:))
        let note = nonEmpty(raw[safe: 5])

        if kind == .monthNote {
            guard let note else { return nil }
            return ReconciliationCSVRow(kind: .monthNote, note: note)
        }

        guard let amount = nonEmpty(raw[safe: 4]).flatMap(parseAmount) else {
            return nil
        }
        if kind == .cashAdjustment, direction == nil {
            return nil
        }
        if kind == .openingBalance || kind == .closingBalance || kind == .interest, account == nil {
            return nil
        }

        return ReconciliationCSVRow(
            kind: kind,
            account: account,
            title: title,
            direction: direction,
            amount: amount,
            note: note
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 금액 파싱 — 천 단위 구분자(콤마)를 제거하고 정수로.
    private static func parseAmount(_ raw: String) -> Int? {
        Int(raw.replacingOccurrences(of: ",", with: ""))
    }
}

struct ReconciliationCSVWriter {
    let folder: URL

    private static let bom = "\u{FEFF}"
    private static let header = "종류,항목,계좌,방향,금액,메모"

    func replaceMonth(monthKey key: String, rows: [ReconciliationCSVRow]) throws {
        let url = folder.appendingPathComponent(Self.filename(forMonthKey: key))
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                if rows.isEmpty {
                    if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                        try FileManager.default.removeItem(at: coordinatedURL)
                    }
                    return
                }
                var contents = Self.bom + Self.header + "\n"
                contents += rows.map { csvLine($0) }.joined(separator: "\n") + "\n"
                try Data(contents.utf8).write(to: coordinatedURL, options: .atomic)
            } catch {
                thrown = error
            }
        }
        if let err = coordinationError { throw err }
        if let err = thrown { throw err }
    }

    nonisolated static func filename(forMonthKey key: String) -> String {
        "reconciliations-\(key).csv"
    }

    private func csvLine(_ row: ReconciliationCSVRow) -> String {
        [
            row.kind.rawValue,
            CSVField.escape(row.title ?? ""),
            CSVField.escape(row.account ?? ""),
            row.direction?.label ?? "",
            row.amount.map { String($0) } ?? "",
            CSVField.escape(row.note ?? ""),
        ].joined(separator: ",")
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
