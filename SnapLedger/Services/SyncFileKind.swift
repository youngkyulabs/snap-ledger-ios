enum SyncFileKind: String, Equatable, Hashable, Sendable {
    case expenses
    case reconciliation

    var label: String {
        switch self {
        case .expenses: "지출"
        case .reconciliation: "정산"
        }
    }

    var sortOrder: Int {
        switch self {
        case .expenses: 0
        case .reconciliation: 1
        }
    }

    func filename(forMonthKey key: String) -> String {
        switch self {
        case .expenses: CSVWriter.filename(forMonthKey: key)
        case .reconciliation: ReconciliationCSVWriter.filename(forMonthKey: key)
        }
    }

    nonisolated static func fileKindAndMonthKey(fromFilename name: String) -> (kind: SyncFileKind, key: String)? {
        if let key = SyncCoordinator.monthKey(fromFilename: name) {
            return (.expenses, key)
        }
        if let key = ReconciliationCSVWriter.monthKey(fromFilename: name) {
            return (.reconciliation, key)
        }
        return nil
    }
}
