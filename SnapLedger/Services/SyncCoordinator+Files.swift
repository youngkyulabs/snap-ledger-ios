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
    /// True for expenses-YYYY-MM.csv, reconciliations-YYYY-MM.csv and budgets-YYYY-MM.csv.
    nonisolated static func isMonthlyExportFilename(_ name: String) -> Bool {
        name.wholeMatch(of: /^(expenses|reconciliations|budgets)-\d{4}-\d{2}\.csv$/) != nil
    }

    /// Deletes monthly export files in the folder whose names are not in `keep`.
    func pruneMonthlyExports(in folderURL: URL, keeping keep: Set<String>) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
        for name in names where Self.isMonthlyExportFilename(name) && !keep.contains(name) {
            try Self.delete(folderURL.appendingPathComponent(name))
        }
    }

    private static func delete(_ url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: (any Error)?
        unsafe coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                thrown = error
            }
        }
        if let err = coordinationError { throw err }
        if let err = thrown { throw err }
    }
}
