import Foundation

extension SyncCoordinator {
    /// `expenses-2026-05.csv` → `2026-05`. 패턴이 안 맞으면 nil. (`SyncFileKind`가 사용)
    nonisolated static func monthKey(fromFilename name: String) -> String? {
        CSVWriter.monthKey(fromFilename: name, prefix: "expenses-")
    }

    nonisolated static func intMonthKey(from key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return 0
        }
        return year * 100 + month
    }

    nonisolated static func monthKeyString(from key: Int) -> String {
        String(format: "%04d-%02d", key / 100, key % 100)
    }
}
