import Foundation
import SwiftData

@MainActor
extension SyncCoordinator {
    private struct BalanceImportState {
        var byAccount: [String: AccountMonthlyBalance] = [:]
        var accountOrder: [String] = []
    }

    func exportReconciliationMonths(_ keys: [String], folderURL: URL, in context: ModelContext) throws {
        let writer = ReconciliationCSVWriter(folder: folderURL)
        let store = ReconciliationStore()
        for key in keys {
            try writer.replaceMonth(monthKey: key, rows: store.rows(for: Self.intMonthKey(from: key), in: context))
            refreshFileState(monthKey: key, kind: .reconciliation, folderURL: folderURL, in: context)
        }
    }

    func replaceReconciliationMonth(
        monthKey key: String,
        rows: [ReconciliationCSVRow],
        in context: ModelContext
    ) {
        let month = Self.intMonthKey(from: key)
        ReconciliationStore().deleteMonth(month, in: context)
        guard !rows.isEmpty else { return }

        let reconciliation = MonthlyReconciliation(monthKey: month)
        var balanceState = BalanceImportState()

        for row in rows {
            apply(row, to: reconciliation, month: month, balanceState: &balanceState, in: context)
        }

        context.insert(reconciliation)
        for account in balanceState.accountOrder {
            if let balance = balanceState.byAccount[account] {
                context.insert(balance)
            }
        }
    }

    func reconciliationMonthKeys(in context: ModelContext) -> Set<String> {
        let reconciliationKeys = ((try? context.fetch(FetchDescriptor<MonthlyReconciliation>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let balanceKeys = ((try? context.fetch(FetchDescriptor<AccountMonthlyBalance>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let adjustmentKeys = ((try? context.fetch(FetchDescriptor<CashAdjustment>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        return Set(reconciliationKeys + balanceKeys + adjustmentKeys)
    }

    private func apply(
        _ row: ReconciliationCSVRow,
        to reconciliation: MonthlyReconciliation,
        month: Int,
        balanceState: inout BalanceImportState,
        in context: ModelContext
    ) {
        switch row.kind {
        case .salary:
            reconciliation.salaryAmount = row.amount
            reconciliation.note = row.note
        case .creditCard:
            reconciliation.creditCardAmount = row.amount
        case .savings:
            reconciliation.savingsAmount = row.amount
        case .openingBalance, .closingBalance, .interest:
            applyBalanceRow(row, month: month, balanceState: &balanceState)
        case .cashAdjustment:
            insertAdjustment(row, month: month, in: context)
        }
    }

    private func applyBalanceRow(
        _ row: ReconciliationCSVRow,
        month: Int,
        balanceState: inout BalanceImportState
    ) {
        guard let account = row.account else { return }
        let balance = balance(account, month: month, balanceState: &balanceState)
        switch row.kind {
        case .openingBalance:
            balance.openingBalance = row.amount
        case .closingBalance:
            balance.closingBalance = row.amount
        case .interest:
            balance.interestAmount = row.amount
        case .salary, .creditCard, .savings, .cashAdjustment:
            break
        }
    }

    private func insertAdjustment(_ row: ReconciliationCSVRow, month: Int, in context: ModelContext) {
        guard let date = row.date, let direction = row.direction else { return }
        context.insert(
            CashAdjustment(
                monthKey: month,
                date: date,
                title: row.title ?? row.kind.rawValue,
                direction: direction,
                amount: row.amount,
                note: row.note
            )
        )
    }

    private func balance(
        _ account: String,
        month: Int,
        balanceState: inout BalanceImportState
    ) -> AccountMonthlyBalance {
        if let existing = balanceState.byAccount[account] {
            return existing
        }
        let created = AccountMonthlyBalance(monthKey: month, accountName: account, sortOrder: balanceState.accountOrder.count)
        balanceState.byAccount[account] = created
        balanceState.accountOrder.append(account)
        return created
    }
}
