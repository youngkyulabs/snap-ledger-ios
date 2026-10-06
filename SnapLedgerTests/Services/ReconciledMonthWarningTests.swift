// swiftlint:disable force_unwrapping

import Foundation
import SwiftData
import Testing
@testable import SnapLedger

/// Verifies the warning shown when adding an entry to a month whose reconciliation came out balanced.
@MainActor
struct ReconciledMonthWarningTests {
    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        DateComponents(
            calendar: .current,
            year: year, month: month, day: day, hour: hour, minute: minute
        ).date!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        return ModelContext(container)
    }

    private func saved(_ date: Date, amount: Int) -> SavedEntry {
        SavedEntry(date: date, amount: amount, merchant: "M", category: "식비", csvFile: "expenses.csv")
    }

    /// Builds a summary for `month` whose account dropped by 200,000 and whose entries record `recorded`.
    private func summary(month: Int, recorded: Int) -> ReconciliationSummary {
        let entryDate = makeDate(year: month / 100, month: month % 100, day: 10)
        return ReconciliationSummary.compute(
            entries: [saved(entryDate, amount: recorded)],
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

    @Test func warnsWhenClosedMonthIsBalanced() {
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 8, day: 20)
        #expect(
            ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: summary(month: 202_608, recorded: 200_000)
            )
        )
    }

    @Test func doesNotWarnWhileClosedMonthHasDifference() {
        // A remaining difference means reconciliation is unfinished; the entry may be the missing one.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 8, day: 20)
        #expect(
            !ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: summary(month: 202_608, recorded: 150_000)
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
                entryDate: entryDate, today: today, summary: summary(month: 202_609, recorded: 200_000)
            )
        )
    }

    @Test func doesNotWarnWhenSummaryDescribesAnotherMonth() {
        // Guards against comparing an entry against the wrong month's summary.
        let today = makeDate(year: 2026, month: 9, day: 15)
        let entryDate = makeDate(year: 2026, month: 7, day: 10)
        #expect(
            !ReconciledMonthWarning.shouldWarn(
                entryDate: entryDate, today: today, summary: summary(month: 202_608, recorded: 200_000)
            )
        )
    }

    @Test func messageNamesTheMonth() {
        let message = ReconciledMonthWarning.message(monthKey: 202_608)
        #expect(message.contains("2026년 8월"))
    }

    @Test func guardWarnsOnlyWhileStoredMonthIsBalanced() throws {
        let context = try makeContext()
        var draft = ReconciliationDraft()
        draft.balances = [BalanceDraft(accountName: "주거래", opening: 1_000_000, closing: 800_000)]
        try ReconciliationStore().save(draft, month: 202_608, in: context)
        // Entries at the month's first instant and on its last day must both count toward the recorded total.
        context.insert(saved(makeDate(year: 2026, month: 8, day: 1, hour: 0), amount: 120_000))
        context.insert(saved(makeDate(year: 2026, month: 8, day: 31, hour: 23, minute: 30), amount: 80_000))
        try context.save()
        let today = makeDate(year: 2026, month: 9, day: 15)
        let newEntryDate = makeDate(year: 2026, month: 8, day: 20)

        #expect(ReconciledMonthGuard.warningMessage(for: newEntryDate, in: context, today: today) != nil)

        // Once an addition opens a difference, further additions no longer warn.
        context.insert(saved(makeDate(year: 2026, month: 8, day: 25), amount: 5_000))
        try context.save()
        #expect(ReconciledMonthGuard.warningMessage(for: newEntryDate, in: context, today: today) == nil)
    }
}
