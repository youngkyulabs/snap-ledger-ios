import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "reconciliation")

/// In-memory draft state for monthly reconciliation editor.
struct ReconciliationDraft: Equatable {
    var incomes: [IncomeItemDraft] = []
    var cards: [CardUsageItemDraft] = []
    var savings: [SavingsItemDraft] = []
    var note: String = ""
    var balances: [BalanceDraft] = []
    var adjustments: [AdjustmentDraft] = []

    /// Whether all draft fields are empty.
    var isEmpty: Bool {
        incomes.isEmpty && cards.isEmpty && savings.isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && balances.isEmpty && adjustments.isEmpty
    }
}

struct IncomeItemDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var amount: Int
    var sortOrder: Int = 0
}

struct SavingsItemDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var amount: Int
    var sortOrder: Int = 0
}

struct CardUsageItemDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var amount: Int
    var sortOrder: Int = 0
}

struct BalanceDraft: Identifiable, Equatable {
    var id = UUID()
    var accountName: String
    var sortOrder: Int = 0
    var opening: Int = 0
    var closing: Int = 0
    var interest: Int = 0
}

struct AdjustmentDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var direction: CashAdjustmentDirection
    var amount: Int
    var note: String?
    var sortOrder: Int = 0
}

@MainActor
struct ReconciliationStore {
    // MARK: - Load (DB -> Draft)

    /// Loads or carries forward draft state for the given month.
    func loadDraft(for month: Int, in context: ModelContext) -> ReconciliationDraft {
        let reconciliation = fetchReconciliation(month, in: context)
        let balances = fetchBalances(month, in: context)
        let adjustments = fetchAdjustments(month, in: context)
        let savingsItems = fetchSavings(month, in: context)
        let cardItems = fetchCards(month, in: context)
        let incomeItems = fetchIncomes(month, in: context)

        if reconciliation == nil, balances.isEmpty, adjustments.isEmpty,
           savingsItems.isEmpty, cardItems.isEmpty, incomeItems.isEmpty {
            return carryForwardDraft(for: month, in: context)
        }

        var draft = ReconciliationDraft()
        if let reconciliation {
            draft.note = reconciliation.note ?? ""
        }
        draft.incomes = incomeDrafts(items: incomeItems)
        draft.cards = cardDrafts(items: cardItems)
        draft.savings = savingsItems.map {
            SavingsItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder)
        }
        draft.balances = balances.map {
            BalanceDraft(
                accountName: $0.accountName,
                sortOrder: $0.sortOrder,
                opening: $0.openingBalance,
                closing: $0.closingBalance,
                interest: $0.interestAmount
            )
        }
        draft.adjustments = adjustments.map {
            AdjustmentDraft(
                title: $0.title,
                direction: $0.direction,
                amount: $0.amount,
                note: $0.note,
                sortOrder: $0.sortOrder
            )
        }
        return draft
    }

    /// Prefills draft state using previous month balances and items.
    private func carryForwardDraft(for month: Int, in context: ModelContext) -> ReconciliationDraft {
        let previous = Self.previousMonthKey(month)
        var draft = ReconciliationDraft()
        draft.incomes = incomeDrafts(items: fetchIncomes(previous, in: context))
        // Carry forward card item titles with 0 amounts
        draft.cards = fetchCards(previous, in: context).map {
            CardUsageItemDraft(title: $0.title, amount: 0, sortOrder: $0.sortOrder)
        }
        // Carry forward adjustment titles with 0 amounts
        draft.adjustments = fetchAdjustments(previous, in: context).map {
            AdjustmentDraft(
                title: $0.title,
                direction: $0.direction,
                amount: 0,
                note: nil,
                sortOrder: $0.sortOrder
            )
        }
        draft.savings = fetchSavings(previous, in: context).map {
            SavingsItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder)
        }
        draft.balances = fetchBalances(previous, in: context).map {
            BalanceDraft(
                accountName: $0.accountName,
                sortOrder: $0.sortOrder,
                opening: $0.closingBalance,
                closing: $0.closingBalance,
                interest: 0
            )
        }
        return draft
    }

    /// Maps CardUsageItem models to drafts.
    private func cardDrafts(items: [CardUsageItem]) -> [CardUsageItemDraft] {
        items.map { CardUsageItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder) }
    }

    /// Maps IncomeItem models to drafts.
    private func incomeDrafts(items: [IncomeItem]) -> [IncomeItemDraft] {
        items.map { IncomeItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder) }
    }

    // MARK: - Save (Draft -> DB + CSV)

    /// Saves reconciliation draft to SwiftData and exports CSV.
    @discardableResult
    func save(
        _ draft: ReconciliationDraft,
        month: Int,
        in context: ModelContext
    ) throws -> Bool {
        replaceMonth(month, with: draft, in: context)
        try context.save()
        return exportBestEffort(month: month, in: context)
    }

    /// Best-effort export of reconciliation and budget CSV.
    private func exportBestEffort(month: Int, in context: ModelContext) -> Bool {
        let key = Self.monthString(from: month)
        do {
            try CSVFolderAccess.withFolder(in: context) { folderURL in
                let sync = SyncCoordinator()
                try sync.exportReconciliationMonths([key], folderURL: folderURL, in: context)
                try sync.exportBudgetMonths([key], folderURL: folderURL, in: context)
            }
            return true
        } catch CSVFolderAccess.AccessError.noCSVFolder {
            // Skip silently if no folder is configured
            return false
        } catch {
            log.error("정산 CSV export(best-effort) failed: \(String(describing: error))")
            return false
        }
    }

    func rows(for month: Int, in context: ModelContext) -> [ReconciliationCSVRow] {
        let reconciliation = fetchReconciliation(month, in: context)
        let balances = fetchBalances(month, in: context)
        let adjustments = fetchAdjustments(month, in: context)
        let savingsItems = fetchSavings(month, in: context)
        let cardItems = fetchCards(month, in: context)

        let incomeItems = fetchIncomes(month, in: context)

        var rows: [ReconciliationCSVRow] = []
        for income in incomeDrafts(items: incomeItems) {
            rows.append(
                ReconciliationCSVRow(kind: .income, title: income.title, amount: income.amount)
            )
        }
        for card in cardDrafts(items: cardItems) {
            rows.append(
                ReconciliationCSVRow(kind: .creditCard, title: card.title, amount: card.amount)
            )
        }
        for item in savingsItems {
            rows.append(
                ReconciliationCSVRow(kind: .savings, title: item.title, amount: item.amount)
            )
        }
        for balance in balances {
            rows.append(
                ReconciliationCSVRow(
                    kind: .openingBalance,
                    account: balance.accountName,
                    amount: balance.openingBalance
                )
            )
            rows.append(
                ReconciliationCSVRow(
                    kind: .closingBalance,
                    account: balance.accountName,
                    amount: balance.closingBalance
                )
            )
            rows.append(
                ReconciliationCSVRow(kind: .interest, account: balance.accountName, amount: balance.interestAmount)
            )
        }
        for adjustment in adjustments {
            rows.append(
                ReconciliationCSVRow(
                    kind: .cashAdjustment,
                    title: adjustment.title,
                    direction: adjustment.direction,
                    amount: adjustment.amount,
                    note: adjustment.note
                )
            )
        }
        if let note = reconciliation?.note, !note.isEmpty {
            rows.append(ReconciliationCSVRow(kind: .monthNote, note: note))
        }
        return rows
    }

    /// Deletes all reconciliation and item records for the month.
    func deleteMonth(_ month: Int, in context: ModelContext) {
        for item in fetchAllReconciliations(in: context) where item.monthKey == month {
            context.delete(item)
        }
        for item in fetchAllBalances(in: context) where item.monthKey == month {
            context.delete(item)
        }
        for item in fetchAllAdjustments(in: context) where item.monthKey == month {
            context.delete(item)
        }
        for item in fetchAllSavings(in: context) where item.monthKey == month {
            context.delete(item)
        }
        for item in fetchAllCards(in: context) where item.monthKey == month {
            context.delete(item)
        }
        for item in fetchAllIncomes(in: context) where item.monthKey == month {
            context.delete(item)
        }
    }

    static func monthString(from key: Int) -> String {
        String(format: "%04d-%02d", key / 100, key % 100)
    }

    static func previousMonthKey(_ key: Int) -> Int {
        let year = key / 100
        let month = key % 100
        if month == 1 { return (year - 1) * 100 + 12 }
        return year * 100 + month - 1
    }

    // MARK: - Private

    private func replaceMonth(_ month: Int, with draft: ReconciliationDraft, in context: ModelContext) {
        deleteMonth(month, in: context)
        guard !draft.isEmpty else { return }

        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(
            MonthlyReconciliation(
                monthKey: month,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
        )
        for (index, item) in draft.incomes.enumerated() {
            context.insert(
                IncomeItem(
                    monthKey: month,
                    title: item.title,
                    amount: item.amount,
                    sortOrder: index
                )
            )
        }
        for (index, item) in draft.cards.enumerated() {
            context.insert(
                CardUsageItem(
                    monthKey: month,
                    title: item.title,
                    amount: item.amount,
                    sortOrder: index
                )
            )
        }
        for (index, item) in draft.savings.enumerated() {
            context.insert(
                SavingsItem(
                    monthKey: month,
                    title: item.title,
                    amount: item.amount,
                    sortOrder: index
                )
            )
        }
        for (index, balance) in draft.balances.enumerated() {
            context.insert(
                AccountMonthlyBalance(
                    monthKey: month,
                    accountName: balance.accountName,
                    sortOrder: index,
                    openingBalance: balance.opening,
                    closingBalance: balance.closing,
                    interestAmount: balance.interest
                )
            )
        }
        for (index, adjustment) in draft.adjustments.enumerated() {
            context.insert(
                CashAdjustment(
                    monthKey: month,
                    title: adjustment.title,
                    direction: adjustment.direction,
                    amount: adjustment.amount,
                    sortOrder: index,
                    note: adjustment.note
                )
            )
        }
    }
}

// MARK: - Fetch Helpers

extension ReconciliationStore {
    private func fetchReconciliation(_ month: Int, in context: ModelContext) -> MonthlyReconciliation? {
        fetchAllReconciliations(in: context).first { $0.monthKey == month }
    }

    private func fetchBalances(_ month: Int, in context: ModelContext) -> [AccountMonthlyBalance] {
        fetchAllBalances(in: context)
            .filter { $0.monthKey == month }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.accountName < $1.accountName : $0.sortOrder < $1.sortOrder }
    }

    private func fetchAdjustments(_ month: Int, in context: ModelContext) -> [CashAdjustment] {
        fetchAllAdjustments(in: context)
            .filter { $0.monthKey == month }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.title < $1.title : $0.sortOrder < $1.sortOrder }
    }

    private func fetchSavings(_ month: Int, in context: ModelContext) -> [SavingsItem] {
        fetchAllSavings(in: context)
            .filter { $0.monthKey == month }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.title < $1.title : $0.sortOrder < $1.sortOrder }
    }

    private func fetchCards(_ month: Int, in context: ModelContext) -> [CardUsageItem] {
        fetchAllCards(in: context)
            .filter { $0.monthKey == month }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.title < $1.title : $0.sortOrder < $1.sortOrder }
    }

    private func fetchIncomes(_ month: Int, in context: ModelContext) -> [IncomeItem] {
        fetchAllIncomes(in: context)
            .filter { $0.monthKey == month }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.title < $1.title : $0.sortOrder < $1.sortOrder }
    }

    private func fetchAllReconciliations(in context: ModelContext) -> [MonthlyReconciliation] {
        (try? context.fetch(FetchDescriptor<MonthlyReconciliation>())) ?? []
    }

    private func fetchAllBalances(in context: ModelContext) -> [AccountMonthlyBalance] {
        (try? context.fetch(FetchDescriptor<AccountMonthlyBalance>())) ?? []
    }

    private func fetchAllAdjustments(in context: ModelContext) -> [CashAdjustment] {
        (try? context.fetch(FetchDescriptor<CashAdjustment>())) ?? []
    }

    private func fetchAllSavings(in context: ModelContext) -> [SavingsItem] {
        (try? context.fetch(FetchDescriptor<SavingsItem>())) ?? []
    }

    private func fetchAllCards(in context: ModelContext) -> [CardUsageItem] {
        (try? context.fetch(FetchDescriptor<CardUsageItem>())) ?? []
    }

    private func fetchAllIncomes(in context: ModelContext) -> [IncomeItem] {
        (try? context.fetch(FetchDescriptor<IncomeItem>())) ?? []
    }
}

extension ReconciliationDraft {
    /// Computes reconciliation summary from unpersisted draft state.
    func summary(entries: [SavedEntry], month: Int, calendar: Calendar = .current) -> ReconciliationSummary {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReconciliationSummary.compute(
            entries: entries,
            input: summaryInput(month: month, trimmedNote: trimmedNote),
            targetMonth: month,
            calendar: calendar
        )
    }

    private func summaryInput(month: Int, trimmedNote: String) -> ReconciliationSummaryInput {
        ReconciliationSummaryInput(
            reconciliation: MonthlyReconciliation(
                monthKey: month,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            ),
            balances: balances.map {
                AccountMonthlyBalance(
                    monthKey: month,
                    accountName: $0.accountName,
                    sortOrder: $0.sortOrder,
                    openingBalance: $0.opening,
                    closingBalance: $0.closing,
                    interestAmount: $0.interest
                )
            },
            adjustments: adjustments.map {
                CashAdjustment(
                    monthKey: month,
                    title: $0.title,
                    direction: $0.direction,
                    amount: $0.amount,
                    sortOrder: $0.sortOrder,
                    note: $0.note
                )
            },
            savingsItems: savings.enumerated().map { index, item in
                SavingsItem(monthKey: month, title: item.title, amount: item.amount, sortOrder: index)
            },
            cardItems: cards.enumerated().map { index, item in
                CardUsageItem(monthKey: month, title: item.title, amount: item.amount, sortOrder: index)
            },
            incomeItems: incomes.enumerated().map { index, item in
                IncomeItem(monthKey: month, title: item.title, amount: item.amount, sortOrder: index)
            }
        )
    }
}
