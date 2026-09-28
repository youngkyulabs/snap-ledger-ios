import Foundation

extension SyncCoordinator {
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
        "\((key / 100).zeroPadded(4))-\((key % 100).zeroPadded(2))"
    }
}

extension SyncCoordinator {
    /// Month keys ("YYYY-MM") that have data, per export kind.
    nonisolated struct ExportMonths: Equatable {
        var expenses: Set<String> = []
        var reconciliations: Set<String> = []
        var budgets: Set<String> = []
    }

    /// Monthly export files whose month has no data; a kind with no data at all is left alone, since an unsynced store looks empty.
    nonisolated static func staleExportNames(_ names: [String], months: ExportMonths) -> [String] {
        names.filter { name in
            guard let match = name.wholeMatch(of: /(expenses|reconciliations|budgets)-([0-9]{4}-[0-9]{2})\.csv/) else {
                return false
            }
            let kept = switch match.output.1 {
            case "expenses": months.expenses
            case "reconciliations": months.reconciliations
            default: months.budgets
            }
            return !kept.isEmpty && !kept.contains(String(match.output.2))
        }
    }
}
