#if DEBUG
import Foundation

/// Parsed expense seed DTO.
struct ExpenseSeed: Equatable {
    let date: Date
    let merchant: String
    let category: String?
    let amount: Int
    let note: String?
}

/// Pure parser converting sample CSV text to seed DTOs.
enum SampleDataParsing {
    /// Parses yyyy-MM-dd into noon Date in current calendar.
    static func parseDate(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    /// Parses expense CSV text into ExpenseSeed array.
    static func parseExpenses(_ csv: String) -> [ExpenseSeed] {
        let rows = CSVParser.parse(csv)
        guard !rows.isEmpty else { return [] }
        var seeds: [ExpenseSeed] = []
        for row in rows.dropFirst() {
            guard row.count >= 4,
                  let date = parseDate(row[0].trimmingCharacters(in: .whitespaces)),
                  let amount = Int(row[3].replacingOccurrences(of: ",", with: "")) else {
                continue
            }
            let merchant = row[1].trimmingCharacters(in: .whitespaces)
            let category = nonEmpty(row[2])
            let note = row.count >= 5 ? nonEmpty(row[4]) : nil
            seeds.append(ExpenseSeed(date: date, merchant: merchant, category: category, amount: amount, note: note))
        }
        return seeds
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parses reconciliation CSV text into ReconciliationDraft.
    static func parseReconciliationDraft(_ csv: String) -> ReconciliationDraft {
        let rows = ReconciliationCSVParser.parse(csv).rows
        var draft = ReconciliationDraft()
        var balanceOrder: [String] = []
        var balanceByName: [String: BalanceDraft] = [:]

        for row in rows {
            applyRow(row, into: &draft, balanceOrder: &balanceOrder, balanceByName: &balanceByName)
        }

        draft.balances = balanceOrder.map { name in
            var balance = balanceByName[name] ?? BalanceDraft(accountName: name)
            // Default closing balance to opening balance if omitted
            if !hasClosingRow(rows, accountName: name) {
                balance.closing = balance.opening
            }
            return balance
        }
        return draft
    }

    private static func applyRow(
        _ row: ReconciliationCSVRow,
        into draft: inout ReconciliationDraft,
        balanceOrder: inout [String],
        balanceByName: inout [String: BalanceDraft]
    ) {
        switch row.kind {
        case .income:
            draft.incomes.append(IncomeItemDraft(title: row.title ?? "", amount: row.amount ?? 0,
                                                 sortOrder: draft.incomes.count))
        case .creditCard:
            upsertCard(title: row.title ?? "", into: &draft) { $0.amount = row.amount ?? 0 }
        case .previousCreditCard:
            upsertCard(title: row.title ?? "", into: &draft) { $0.previousAmount = row.amount ?? 0 }
        case .savings:
            draft.savings.append(SavingsItemDraft(title: row.title ?? "", amount: row.amount ?? 0,
                                                  sortOrder: draft.savings.count))
        case .cashAdjustment:
            draft.adjustments.append(AdjustmentDraft(
                title: row.title ?? "",
                direction: row.direction ?? .withdrawal,
                amount: row.amount ?? 0,
                note: row.note,
                sortOrder: draft.adjustments.count))
        case .monthNote:
            draft.note = row.note ?? ""
        case .openingBalance, .closingBalance, .interest:
            applyBalanceRow(row, balanceOrder: &balanceOrder, balanceByName: &balanceByName)
        }
    }

    /// Merges a card row onto the existing item with the same title, appending when absent.
    private static func upsertCard(
        title: String,
        into draft: inout ReconciliationDraft,
        apply: (inout CardUsageItemDraft) -> Void
    ) {
        if let index = draft.cards.firstIndex(where: { $0.title == title }) {
            apply(&draft.cards[index])
            return
        }
        var card = CardUsageItemDraft(title: title, amount: 0, sortOrder: draft.cards.count)
        apply(&card)
        draft.cards.append(card)
    }

    private static func applyBalanceRow(
        _ row: ReconciliationCSVRow,
        balanceOrder: inout [String],
        balanceByName: inout [String: BalanceDraft]
    ) {
        let name = row.title ?? row.account ?? ""
        if balanceByName[name] == nil {
            balanceByName[name] = BalanceDraft(accountName: name, sortOrder: balanceOrder.count)
            balanceOrder.append(name)
        }
        let amount = row.amount ?? 0
        switch row.kind {
        case .openingBalance: balanceByName[name]?.opening = amount
        case .closingBalance: balanceByName[name]?.closing = amount
        case .interest: balanceByName[name]?.interest = amount
        default: break
        }
    }

    private static func hasClosingRow(_ rows: [ReconciliationCSVRow], accountName: String) -> Bool {
        rows.contains { $0.kind == .closingBalance && ($0.title ?? $0.account ?? "") == accountName }
    }
}
#endif
