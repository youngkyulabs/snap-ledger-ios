import Foundation

struct BudgetCSVRow: Equatable, Sendable {
    let category: String
    let limit: Int
}

struct BudgetCSVWriter {
    let folder: URL

    private static let bom = "\u{FEFF}"
    private static let header = "카테고리,한도"

    func replaceMonth(monthKey key: String, rows: [BudgetCSVRow]) throws {
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
        "budgets-\(key).csv"
    }

    private func csvLine(_ row: BudgetCSVRow) -> String {
        [Self.escape(row.category), String(row.limit)].joined(separator: ",")
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
