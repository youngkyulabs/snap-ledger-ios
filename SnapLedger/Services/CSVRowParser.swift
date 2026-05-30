import Foundation

/// 외부에서 편집됐을 수 있는 CSV 텍스트를 `SavedRow` 목록으로 파싱한다 (파일 → 앱 import).
/// 날짜(`yyyy-MM-dd`)·금액(정수) 파싱에 실패한 행은 건너뛰고 카운트해 호출자에게 보고한다.
enum CSVRowParser {
    struct Result: Equatable {
        var rows: [SavedRow]
        var skipped: Int
    }

    static func parse(_ text: String, calendar: Calendar = .current) -> Result {
        parse(table: CSVParser.parse(text), calendar: calendar)
    }

    static func parse(table: [[String]], calendar: Calendar = .current) -> Result {
        guard !table.isEmpty else { return Result(rows: [], skipped: 0) }

        var body = table
        if let first = table.first, isHeader(first) {
            body = Array(table.dropFirst())
        }

        var rows: [SavedRow] = []
        var skipped = 0
        for cols in body {
            if cols.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                continue
            }
            if let row = row(from: cols, calendar: calendar) {
                rows.append(row)
            } else {
                skipped += 1
            }
        }
        return Result(rows: rows, skipped: skipped)
    }

    private static func isHeader(_ row: [String]) -> Bool {
        guard let first = row.first else { return false }
        if first.trimmingCharacters(in: .whitespaces) == "날짜" { return true }
        if row.count > 3, amount(from: row[3]) == nil { return true }
        return false
    }

    private static func row(from cols: [String], calendar: Calendar) -> SavedRow? {
        guard cols.count >= 4 else { return nil }
        guard let date = date(from: cols[0], calendar: calendar) else { return nil }
        guard let amount = amount(from: cols[3]) else { return nil }
        let description = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let category = nilIfEmpty(cols[2])
        let note = cols.count > 4 ? nilIfEmpty(cols[4]) : nil
        return SavedRow(
            date: date,
            description: description,
            category: category,
            amount: amount,
            note: note
        )
    }

    private static func amount(from raw: String) -> Int? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Int(cleaned)
    }

    private static func nilIfEmpty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(from raw: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
