import Foundation

struct SavedRow: Equatable, Sendable {
    let date: Date
    let description: String
    let category: String?
    let amount: Int

    init(date: Date, description: String, category: String? = nil, amount: Int) {
        self.date = date
        self.description = description
        self.category = category
        self.amount = amount
    }
}

struct CSVWriter {
    let folder: URL
    let calendar: Calendar

    private static let bom = "\u{FEFF}"
    private static let header = "날짜,설명,카테고리,금액"

    init(folder: URL, calendar: Calendar = .current) {
        self.folder = folder
        self.calendar = calendar
    }

    func append(_ row: SavedRow) throws {
        try append([row])
    }

    func append(_ rows: [SavedRow]) throws {
        guard !rows.isEmpty else { return }
        let groups = Dictionary(grouping: rows) { monthKey(for: $0.date) }
        for (key, groupRows) in groups {
            let url = folder.appendingPathComponent("expenses-\(key).csv")
            try appendRows(groupRows, to: url)
        }
    }

    func replaceMonth(monthKey key: String, rows: [SavedRow]) throws {
        let url = folder.appendingPathComponent("expenses-\(key).csv")
        try replaceRows(rows, at: url)
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func filename(forMonthKey key: String) -> String {
        "expenses-\(key).csv"
    }

    private func monthKey(for date: Date) -> String {
        Self.monthKey(for: date, calendar: calendar)
    }

    private func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func csvLine(_ row: SavedRow) -> String {
        [
            dayKey(for: row.date),
            Self.escape(row.description),
            Self.escape(row.category ?? ""),
            String(row.amount),
        ].joined(separator: ",")
    }

    private func appendRows(_ rows: [SavedRow], to url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(
            writingItemAt: url, options: .forMerging, error: &coordinationError
        ) { coordinatedURL in
            do {
                let fileExisted = FileManager.default.fileExists(atPath: coordinatedURL.path)
                if !fileExisted {
                    let initial = Self.bom + Self.header + "\n"
                    try Data(initial.utf8).write(to: coordinatedURL, options: .atomic)
                }

                let body = rows.map { csvLine($0) }.joined(separator: "\n") + "\n"
                let data = Data(body.utf8)

                let handle = try FileHandle(forWritingTo: coordinatedURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                thrown = error
            }
        }
        if let err = coordinationError { throw err }
        if let err = thrown { throw err }
    }

    private func replaceRows(_ rows: [SavedRow], at url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { coordinatedURL in
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

    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        if needsQuoting {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
