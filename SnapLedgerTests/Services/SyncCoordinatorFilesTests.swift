import Foundation
import Testing
@testable import SnapLedger

struct SyncCoordinatorFilesTests {
    @Test(arguments: [
        ("expenses-2026-05.csv", true),
        ("reconciliations-2026-05.csv", true),
        ("budgets-2026-05.csv", true),
        ("expenses-backup.csv", false),
        ("notes.csv", false),
        ("expenses-2026-5.csv", false),
        ("Expenses-2026-05.csv", false),
        ("expenses-2026-05.csv.bak", false),
    ])
    func isMonthlyExportFilename(name: String, expected: Bool) {
        #expect(SyncCoordinator.isMonthlyExportFilename(name) == expected)
    }
}
