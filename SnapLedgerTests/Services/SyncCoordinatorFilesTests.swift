import Foundation
import Testing
@testable import SnapLedger

struct SyncCoordinatorFilesTests {
    private let months = SyncCoordinator.ExportMonths(
        expenses: ["2026-05"],
        reconciliations: ["2026-03"],
        budgets: ["2026-04"]
    )

    @Test(arguments: [
        ("expenses-2020-01.csv", true),
        ("reconciliations-2020-01.csv", true),
        ("budgets-2020-01.csv", true),
        ("expenses-2026-05.csv", false),
        ("reconciliations-2026-03.csv", false),
        ("budgets-2026-04.csv", false),
        ("expenses-backup.csv", false),
        ("notes.csv", false),
        ("expenses-2026-5.csv", false),
        ("Expenses-2020-01.csv", false),
        ("expenses-2020-01.csv.bak", false),
        ("expenses-２０２０-０１.csv", false),
    ])
    func staleExportNames(name: String, isStale: Bool) {
        #expect(SyncCoordinator.staleExportNames([name], months: months) == (isStale ? [name] : []))
    }

    @Test func kindWithNoDataIsNeverStale() {
        // A budget row that synced first must not make unsynced expense or reconciliation files look stale.
        let budgetsOnly = SyncCoordinator.ExportMonths(budgets: ["2026-09"])
        let names = ["expenses-2020-01.csv", "reconciliations-2020-01.csv", "budgets-2020-01.csv"]
        #expect(SyncCoordinator.staleExportNames(names, months: budgetsOnly) == ["budgets-2020-01.csv"])
    }
}
