import Foundation
import SwiftData

// MARK: - Import 내부 교체 헬퍼 (파일 → 앱)

@MainActor
extension SyncCoordinator {
    /// 그 달의 지출 항목을 파일에서 읽은 행들로 통째로 교체한다. 행 순서를 보존하기 위해
    /// savedAt을 행 순서대로 증가시켜 부여한다 (재export 시 동일 순서).
    func replaceMonthEntries(monthKey key: String, rows: [SavedRow], in context: ModelContext) {
        let filename = CSVWriter.filename(forMonthKey: key)
        let all = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
        for entry in all where CSVWriter.monthKey(for: entry.date) == key {
            context.delete(entry)
        }
        let base = Date()
        for (index, row) in rows.enumerated() {
            context.insert(
                SavedEntry(
                    date: row.date,
                    amount: row.amount,
                    merchant: row.description,
                    category: row.category,
                    note: row.note,
                    savedAt: base.addingTimeInterval(Double(index)),
                    csvFile: filename
                )
            )
        }
    }
}
