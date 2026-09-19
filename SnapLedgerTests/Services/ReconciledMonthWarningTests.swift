// swiftlint:disable force_unwrapping

import Foundation
import Testing
@testable import SnapLedger

/// Verifies the warning shown when adding an entry to an already-reconciled month.
@MainActor
struct ReconciledMonthWarningTests {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: .init(identifier: .gregorian),
            year: year, month: month, day: day
        ).date!
    }

    /// Builds a summary for `month` carrying saved reconciliation data.
    private func reconciledSummary(month: Int) -> ReconciliationSummary {
        ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(
                balances: [
                    AccountMonthlyBalance(
                        monthKey: month,
                        accountName: "주거래",
                        openingBalance: 1_000_000,
                        closingBalance: 800_000
                    ),
                ]
            ),
            targetMonth: month
        )
    }

    private func emptySummary(month: Int) -> ReconciliationSummary {
        ReconciliationSummary.compute(
            entries: [],
            input: ReconciliationSummaryInput(),
            targetMonth: month
        )
    }

    @Test func warnsWhenClosedMonthHasReconciliationData() {
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 8, day: 20)
        #expect(
            ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: reconciledSummary(month: 202_608)
            )
        )
    }

    @Test func doesNotWarnForClosedMonthWithoutReconciliationData() {
        // Past month never reconciled: adding an entry changes nothing already concluded.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 8, day: 20)
        #expect(
            !ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: emptySummary(month: 202_608)
            )
        )
    }

    @Test func doesNotWarnForCurrentMonth() {
        // The current month is still in progress, so entries are expected.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 9, day: 2)
        #expect(
            !ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: reconciledSummary(month: 202_609)
            )
        )
    }

    @Test func doesNotWarnWhenSummaryDescribesAnotherMonth() {
        // Guards against comparing an entry against the wrong month's summary.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 7, day: 10)
        #expect(
            !ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: reconciledSummary(month: 202_608)
            )
        )
    }

    @Test func messageNamesTheMonth() {
        let message = ReconciledMonthWarning.message(monthKey: 202_608)
        #expect(message.contains("2026년 8월"))
    }
}
