import Foundation

struct SavedRow: Equatable, Sendable {
    let date: Date
    let description: String
    let category: String?
    let amount: Int
    let note: String?

    init(
        date: Date,
        description: String,
        category: String? = nil,
        amount: Int,
        note: String? = nil
    ) {
        self.date = date
        self.description = description
        self.category = category
        self.amount = amount
        self.note = note
    }
}

struct CSVWriter {
    let folder: URL
    let calendar: Calendar

    private static let bom = "\u{FEFF}"
    private static let header = "날짜,설명,카테고리,금액,메모"

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

    /// `2026-05` → `2026년 5월`. 사용자 노출 문구에서 월 키를 사람이 읽는 라벨로.
    /// 패턴이 안 맞으면 입력 키를 그대로 반환한다.
    /// `LocalizedError.errorDescription`(nonisolated)에서도 부르므로 `nonisolated`.
    nonisolated static func monthLabel(forMonthKey key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return key
        }
        return "\(year)년 \(month)월"
    }

    /// 여러 월 키를 "2026년 5월, 2026년 6월"처럼 라벨로 이어 붙인다.
    /// 같은 달이 종류별(지출·정산)로 중복돼 들어와도 라벨은 한 번만 보이게 입력 순서를 유지해 중복 제거한다.
    nonisolated static func monthLabels(_ keys: [String]) -> String {
        var seen = Set<String>()
        return keys
            .filter { seen.insert($0).inserted }
            .map { monthLabel(forMonthKey: $0) }
            .joined(separator: ", ")
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
            Self.escape(row.note ?? ""),
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
                } else {
                    try Self.migrateHeaderIfNeeded(at: coordinatedURL)
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

    // 기존 파일의 헤더가 현재 헤더와 다르면 (예: 4열 → 5열 메모 컬럼 추가)
    // 전체를 새 헤더로 재기록한다. 기존 row는 컬럼 수에 맞춰 빈 값을 padding.
    private static func migrateHeaderIfNeeded(at url: URL) throws {
        let existing = try String(contentsOf: url, encoding: .utf8)
        let stripped = existing.hasPrefix("\u{FEFF}") ? String(existing.dropFirst()) : existing
        guard let firstNewline = stripped.firstIndex(of: "\n") else { return }
        let existingHeader = String(stripped[..<firstNewline])
        if existingHeader == header { return }

        let parsedRows = CSVParser.parse(stripped)
        var rebuilt = bom + header + "\n"
        for row in parsedRows.dropFirst() {
            var padded = row
            while padded.count < headerColumnCount {
                padded.append("")
            }
            let trimmed = Array(padded.prefix(headerColumnCount))
            rebuilt += trimmed.map { escape($0) }.joined(separator: ",") + "\n"
        }
        try Data(rebuilt.utf8).write(to: url, options: .atomic)
    }

    private static let headerColumnCount = header.split(separator: ",").count

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
