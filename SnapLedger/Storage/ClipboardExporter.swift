import Foundation

nonisolated enum ClipboardExporter {
    static func tsv(for rows: [SavedRow], calendar: Calendar = .current) -> String {
        rows.map { tsvLine($0, calendar: calendar) }.joined(separator: "\n")
    }

    static func tsv(rows: [[String]]) -> String {
        rows
            .map { row in row.map(sanitize).joined(separator: "\t") }
            .joined(separator: "\n")
    }

    static func html(rows: [[String]], hasHeader: Bool) -> String {
        guard !rows.isEmpty else { return "" }
        var out = "<table>"
        if hasHeader {
            let header = rows[0]
            let body = Array(rows.dropFirst())
            out += "<thead><tr>"
            for cell in header {
                out += "<th>\(htmlEscape(cell))</th>"
            }
            out += "</tr></thead><tbody>"
            for row in body {
                out += "<tr>"
                for cell in row {
                    out += "<td>\(htmlEscape(cell))</td>"
                }
                out += "</tr>"
            }
            out += "</tbody>"
        } else {
            out += "<tbody>"
            for row in rows {
                out += "<tr>"
                for cell in row {
                    out += "<td>\(htmlEscape(cell))</td>"
                }
                out += "</tr>"
            }
            out += "</tbody>"
        }
        out += "</table>"
        return out
    }

    private static func htmlEscape(_ field: String) -> String {
        var s = field
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "\r\n", with: "<br>")
        s = s.replacingOccurrences(of: "\n", with: "<br>")
        s = s.replacingOccurrences(of: "\r", with: "<br>")
        return s
    }

    private static func tsvLine(_ row: SavedRow, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: row.date)
        let dateStr = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return [
            dateStr,
            sanitize(row.description),
            sanitize(row.category ?? ""),
            String(row.amount),
        ].joined(separator: "\t")
    }

    private static func sanitize(_ field: String) -> String {
        var s = field
        s = s.replacingOccurrences(of: "\t", with: " ")
        s = s.replacingOccurrences(of: "\r\n", with: " ")
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: "\r", with: " ")
        return s
    }
}
