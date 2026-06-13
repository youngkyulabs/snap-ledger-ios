import Foundation
import SwiftData

@MainActor
extension SyncCoordinator {
    private struct ImportState {
        var byAccount: [String: AccountMonthlyBalance] = [:]
        var accountOrder: [String] = []
        var incomeOrder = 0
        var savingsOrder = 0
        var cardOrder = 0
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
        var state = ImportState()

        for row in rows {
            applyItemRow(row, to: reconciliation, month: month, state: &state, in: context)
        }

        context.insert(reconciliation)
        for account in state.accountOrder {
            if let balance = state.byAccount[account] {
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
        let savingsKeys = ((try? context.fetch(FetchDescriptor<SavingsItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let cardKeys = ((try? context.fetch(FetchDescriptor<CardUsageItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        let incomeKeys = ((try? context.fetch(FetchDescriptor<IncomeItem>())) ?? [])
            .map { Self.monthKeyString(from: $0.monthKey) }
        return Set(reconciliationKeys + balanceKeys + adjustmentKeys + savingsKeys + cardKeys + incomeKeys)
    }

    private func applyItemRow(
        _ row: ReconciliationCSVRow,
        to reconciliation: MonthlyReconciliation,
        month: Int,
        state: inout ImportState,
        in context: ModelContext
    ) {
        switch row.kind {
        case .income:
            guard let amount = row.amount else { break }
            context.insert(
                IncomeItem(
                    monthKey: month,
                    title: row.title ?? ReconciliationCSVKind.income.rawValue,
                    amount: amount,
                    sortOrder: state.incomeOrder
                )
            )
            state.incomeOrder += 1
        case .savings:
            guard let amount = row.amount else { break }
            context.insert(
                SavingsItem(
                    monthKey: month,
                    title: row.title ?? ReconciliationCSVKind.savings.rawValue,
                    amount: amount,
                    sortOrder: state.savingsOrder
                )
            )
            state.savingsOrder += 1
        case .creditCard:
            guard let amount = row.amount else { break }
            context.insert(
                CardUsageItem(
                    monthKey: month,
                    title: row.title ?? ReconciliationCSVKind.creditCard.rawValue,
                    amount: amount,
                    sortOrder: state.cardOrder
                )
            )
            state.cardOrder += 1
        case .monthNote:
            if let note = row.note { reconciliation.note = note }
        default:
            switch row.kind {
            case .openingBalance, .closingBalance, .interest:
                applyBalanceRow(row, month: month, state: &state)
            case .cashAdjustment:
                insertAdjustment(row, month: month, in: context)
            default:
                break
            }
        }
    }

    private func applyBalanceRow(
        _ row: ReconciliationCSVRow,
        month: Int,
        state: inout ImportState
    ) {
        guard let account = row.account else { return }
        let balance = balance(account, month: month, state: &state)
        guard let amount = row.amount else { return }
        switch row.kind {
        case .openingBalance:
            balance.openingBalance = amount
        case .closingBalance:
            balance.closingBalance = amount
        case .interest:
            balance.interestAmount = amount
        case .income, .creditCard, .savings, .cashAdjustment, .monthNote:
            break
        }
    }

    private func insertAdjustment(_ row: ReconciliationCSVRow, month: Int, in context: ModelContext) {
        guard let direction = row.direction, let amount = row.amount else { return }
        context.insert(
            CashAdjustment(
                monthKey: month,
                // CSV는 자금변동 날짜를 담지 않는다(정산은 월 단위) — import 시 그 달 1일로 합성.
                date: ReconciliationStore.date(month: month),
                title: row.title ?? row.kind.rawValue,
                direction: direction,
                amount: amount,
                note: row.note
            )
        )
    }

    private func balance(
        _ account: String,
        month: Int,
        state: inout ImportState
    ) -> AccountMonthlyBalance {
        if let existing = state.byAccount[account] {
            return existing
        }
        let created = AccountMonthlyBalance(monthKey: month, accountName: account, sortOrder: state.accountOrder.count)
        state.byAccount[account] = created
        state.accountOrder.append(account)
        return created
    }
}
