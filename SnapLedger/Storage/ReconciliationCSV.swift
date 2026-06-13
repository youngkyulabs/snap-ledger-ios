import Foundation

enum ReconciliationCSVKind: String, CaseIterable, Sendable {
    /// 레거시 단일 월급 행. 더 이상 쓰지 않지만 과거 CSV를 읽기 위해 유지한다 (수입 항목으로 흡수).
    case salary = "월급"
    case income = "수입"
    case creditCard = "카드사용액"
    case savings = "저축액"
    case openingBalance = "기초잔액"
    case closingBalance = "기말잔액"
    case interest = "이자"
    case cashAdjustment = "자금변동"
}

struct ReconciliationCSVRow: Equatable, Sendable {
    let kind: ReconciliationCSVKind
    let date: Date?
    let account: String?
    let title: String?
    let direction: CashAdjustmentDirection?
    let amount: Int
    let note: String?

    init(
        kind: ReconciliationCSVKind,
        date: Date? = nil,
        account: String? = nil,
        title: String? = nil,
        direction: CashAdjustmentDirection? = nil,
        amount: Int,
        note: String? = nil
    ) {
        self.kind = kind
        self.date = date
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
    static func parse(
        _ content: String,
        calendar: Calendar = .current
    ) -> ReconciliationCSVParseResult {
        let rawRows = CSVParser.parse(content)
        guard !rawRows.isEmpty else {
            return ReconciliationCSVParseResult(rows: [], skipped: 0)
        }

        var rows: [ReconciliationCSVRow] = []
        var skipped = 0
        let body = rawRows.dropFirst()
        for raw in body {
            guard let row = parseRow(raw, calendar: calendar) else {
                skipped += 1
                continue
            }
            rows.append(row)
        }
        return ReconciliationCSVParseResult(rows: rows, skipped: skipped)
    }

    private static func parseRow(_ raw: [String], calendar: Calendar) -> ReconciliationCSVRow? {
        guard raw.count >= 6,
              let kind = ReconciliationCSVKind(rawValue: raw[0]),
              let amount = Int(raw[5]) else {
            return nil
        }
        let date = parseDate(raw[safe: 1] ?? "", calendar: calendar)
        let account = nonEmpty(raw[safe: 2])
        let title = nonEmpty(raw[safe: 3])
        let direction = nonEmpty(raw[safe: 4]).flatMap(CashAdjustmentDirection.from(label:))
        let note = nonEmpty(raw[safe: 6])

        if kind == .cashAdjustment {
            guard date != nil, direction != nil else { return nil }
        }

        return ReconciliationCSVRow(
            kind: kind,
            date: date,
            account: account,
            title: title,
            direction: direction,
            amount: amount,
            note: note
        )
    }

    private static func parseDate(_ value: String, calendar: Calendar) -> Date? {
        guard !value.isEmpty else { return nil }
        var comps = DateComponents()
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        comps.year = year
        comps.month = month
        comps.day = day
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        return calendar.date(from: comps)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ReconciliationCSVWriter {
    let folder: URL
    let calendar: Calendar

    private static let bom = "\u{FEFF}"
    private static let header = "종류,날짜,계좌,항목,방향,금액,메모"

    init(folder: URL, calendar: Calendar = .current) {
        self.folder = folder
        self.calendar = calendar
    }

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

    nonisolated static func monthKey(fromFilename name: String) -> String? {
        CSVWriter.monthKey(fromFilename: name, prefix: "reconciliations-")
    }

    private func csvLine(_ row: ReconciliationCSVRow) -> String {
        [
            row.kind.rawValue,
            row.date.map(dayKey(for:)) ?? "",
            Self.escape(row.account ?? ""),
            Self.escape(row.title ?? ""),
            row.direction?.label ?? "",
            String(row.amount),
            Self.escape(row.note ?? ""),
        ].joined(separator: ",")
    }

    private func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        if needsQuoting {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
