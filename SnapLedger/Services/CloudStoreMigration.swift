import Foundation
import SwiftData

/// Snapshot of CategoryBudget values.
struct BudgetSnapshot: Equatable {
    let category: String
    let monthlyLimit: Int
    let effectiveFrom: Int
    let updatedAt: Date
}

/// Snapshot of SavedEntry values.
struct EntrySnapshot: Equatable {
    let id: UUID
    let date: Date
    let amount: Int
    let merchant: String
    let category: String?
    let note: String?
    let savedAt: Date
    let csvFile: String
}

/// Snapshot of MonthlyReconciliation values.
struct ReconciliationSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let note: String?
    let updatedAt: Date
}

/// Snapshot of AccountMonthlyBalance values.
struct AccountBalanceSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let accountName: String
    let sortOrder: Int
    let openingBalance: Int
    let closingBalance: Int
    let interestAmount: Int
}

/// Snapshot of CashAdjustment values.
struct CashAdjustmentSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let title: String
    let direction: CashAdjustmentDirection
    let amount: Int
    let sortOrder: Int
    let note: String?
}

/// Snapshot of reconciliation line item values.
struct LineItemSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let title: String
    let amount: Int
    let sortOrder: Int
    let updatedAt: Date
}

/// Snapshot of MerchantCategory learning values.
struct MerchantSnapshot: Equatable {
    let merchantNormalized: String
    let category: String
    let updatedAt: Date
}

/// Migration helper for copying legacy unmigrated data to CloudKit store.
enum CloudStoreMigration {
    /// Reads legacy budget data into snapshots.
    @MainActor
    static func snapshotBudgets(from source: ModelContext) -> [BudgetSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        return rows.map {
            BudgetSnapshot(
                category: $0.category,
                monthlyLimit: $0.monthlyLimit,
                effectiveFrom: $0.effectiveFrom,
                updatedAt: $0.updatedAt
            )
        }
    }

    /// Migrates budget snapshots to CloudKit store.
    @MainActor
    static func copyBudgets(_ snapshots: [BudgetSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        var byKey = Dictionary(
            existing.map { ("\($0.category)|\($0.effectiveFrom)", $0) }
        ) { first, _ in first }
        for snap in snapshots {
            let key = "\(snap.category)|\(snap.effectiveFrom)"
            if let row = byKey[key] {
                row.monthlyLimit = snap.monthlyLimit
                row.updatedAt = snap.updatedAt
            } else {
                let row = CategoryBudget(
                    category: snap.category,
                    monthlyLimit: snap.monthlyLimit,
                    effectiveFrom: snap.effectiveFrom,
                    updatedAt: snap.updatedAt
                )
                cloud.insert(row)
                byKey[key] = row
            }
        }
        try? cloud.save()
    }

    /// Inserts category preset records into CloudKit store.
    @MainActor
    static func seedPresets(_ names: [String], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<CategoryPreset>())) ?? []
        let byName = Dictionary(existing.map { ($0.name, $0) }) { first, _ in first }
        for (index, name) in names.enumerated() {
            if let preset = byName[name] {
                preset.sortOrder = index
            } else {
                cloud.insert(CategoryPreset(name: name, sortOrder: index))
            }
        }
        try? cloud.save()
    }

    /// Reads legacy saved entries into snapshots.
    @MainActor
    static func snapshotEntries(from source: ModelContext) -> [EntrySnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<SavedEntry>())) ?? []
        return rows.map {
            EntrySnapshot(
                id: $0.id, date: $0.date, amount: $0.amount,
                merchant: $0.merchant, category: $0.category, note: $0.note,
                savedAt: $0.savedAt, csvFile: $0.csvFile
            )
        }
    }

    /// Migrates saved entry snapshots to CloudKit store.
    @MainActor
    static func copyEntries(_ snapshots: [EntrySnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<SavedEntry>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.date = snap.date
                row.amount = snap.amount
                row.merchant = snap.merchant
                row.category = snap.category
                row.note = snap.note
                row.savedAt = snap.savedAt
                row.csvFile = snap.csvFile
            } else {
                let row = SavedEntry(
                    id: snap.id, date: snap.date, amount: snap.amount,
                    merchant: snap.merchant, category: snap.category, note: snap.note,
                    savedAt: snap.savedAt, csvFile: snap.csvFile
                )
                cloud.insert(row)
                byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - Reconciliation Header

    @MainActor
    static func snapshotReconciliations(from source: ModelContext) -> [ReconciliationSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<MonthlyReconciliation>())) ?? []
        return rows.map { ReconciliationSnapshot(id: $0.id, monthKey: $0.monthKey, note: $0.note, updatedAt: $0.updatedAt) }
    }

    @MainActor
    static func copyReconciliations(_ snapshots: [ReconciliationSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<MonthlyReconciliation>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey
                row.note = snap.note
                row.updatedAt = snap.updatedAt
            } else {
                let row = MonthlyReconciliation(id: snap.id, monthKey: snap.monthKey, note: snap.note, updatedAt: snap.updatedAt)
                cloud.insert(row)
                byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - Account Monthly Balances

    @MainActor
    static func snapshotAccountBalances(from source: ModelContext) -> [AccountBalanceSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<AccountMonthlyBalance>())) ?? []
        return rows.map {
            AccountBalanceSnapshot(
                id: $0.id, monthKey: $0.monthKey, accountName: $0.accountName, sortOrder: $0.sortOrder,
                openingBalance: $0.openingBalance, closingBalance: $0.closingBalance, interestAmount: $0.interestAmount
            )
        }
    }

    @MainActor
    static func copyAccountBalances(_ snapshots: [AccountBalanceSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<AccountMonthlyBalance>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey
                row.accountName = snap.accountName
                row.sortOrder = snap.sortOrder
                row.openingBalance = snap.openingBalance
                row.closingBalance = snap.closingBalance
                row.interestAmount = snap.interestAmount
            } else {
                let row = AccountMonthlyBalance(
                    id: snap.id, monthKey: snap.monthKey, accountName: snap.accountName, sortOrder: snap.sortOrder,
                    openingBalance: snap.openingBalance, closingBalance: snap.closingBalance, interestAmount: snap.interestAmount
                )
                cloud.insert(row)
                byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - Cash Adjustments

    @MainActor
    static func snapshotCashAdjustments(from source: ModelContext) -> [CashAdjustmentSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<CashAdjustment>())) ?? []
        return rows.map {
            CashAdjustmentSnapshot(
                id: $0.id, monthKey: $0.monthKey, title: $0.title,
                direction: $0.direction, amount: $0.amount, sortOrder: $0.sortOrder, note: $0.note
            )
        }
    }

    @MainActor
    static func copyCashAdjustments(_ snapshots: [CashAdjustmentSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<CashAdjustment>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey
                row.title = snap.title
                row.direction = snap.direction
                row.amount = snap.amount
                row.sortOrder = snap.sortOrder
                row.note = snap.note
            } else {
                let row = CashAdjustment(
                    id: snap.id, monthKey: snap.monthKey, title: snap.title,
                    direction: snap.direction, amount: snap.amount, sortOrder: snap.sortOrder, note: snap.note
                )
                cloud.insert(row)
                byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - Line Items (Savings, Cards, Income)

    @MainActor
    static func snapshotSavings(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<SavingsItem>())) ?? []
        return rows.map {
            LineItemSnapshot(
                id: $0.id, monthKey: $0.monthKey, title: $0.title,
                amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt
            )
        }
    }

    @MainActor
    static func copySavings(_ snapshots: [LineItemSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<SavingsItem>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey; row.title = snap.title; row.amount = snap.amount
                row.sortOrder = snap.sortOrder; row.updatedAt = snap.updatedAt
            } else {
                let row = SavingsItem(
                    id: snap.id, monthKey: snap.monthKey, title: snap.title,
                    amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt
                )
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    @MainActor
    static func snapshotCardUsage(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<CardUsageItem>())) ?? []
        return rows.map {
            LineItemSnapshot(
                id: $0.id, monthKey: $0.monthKey, title: $0.title,
                amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt
            )
        }
    }

    @MainActor
    static func copyCardUsage(_ snapshots: [LineItemSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<CardUsageItem>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey; row.title = snap.title; row.amount = snap.amount
                row.sortOrder = snap.sortOrder; row.updatedAt = snap.updatedAt
            } else {
                let row = CardUsageItem(
                    id: snap.id, monthKey: snap.monthKey, title: snap.title,
                    amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt
                )
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    @MainActor
    static func snapshotIncome(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<IncomeItem>())) ?? []
        return rows.map {
            LineItemSnapshot(
                id: $0.id, monthKey: $0.monthKey, title: $0.title,
                amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt
            )
        }
    }

    @MainActor
    static func copyIncome(_ snapshots: [LineItemSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<IncomeItem>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byID[snap.id] {
                row.monthKey = snap.monthKey; row.title = snap.title; row.amount = snap.amount
                row.sortOrder = snap.sortOrder; row.updatedAt = snap.updatedAt
            } else {
                let row = IncomeItem(
                    id: snap.id, monthKey: snap.monthKey, title: snap.title,
                    amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt
                )
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - Merchant Category Learning

    @MainActor
    static func snapshotMerchants(from source: ModelContext) -> [MerchantSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<MerchantCategory>())) ?? []
        return rows.map { MerchantSnapshot(merchantNormalized: $0.merchantNormalized, category: $0.category, updatedAt: $0.updatedAt) }
    }

    @MainActor
    static func copyMerchants(_ snapshots: [MerchantSnapshot], into cloud: ModelContext) {
        let existing = (try? cloud.fetch(FetchDescriptor<MerchantCategory>())) ?? []
        var byKey = Dictionary(existing.map { ($0.merchantNormalized, $0) }) { first, _ in first }
        for snap in snapshots {
            if let row = byKey[snap.merchantNormalized] {
                row.category = snap.category
                row.updatedAt = snap.updatedAt
            } else {
                let row = MerchantCategory(merchantNormalized: snap.merchantNormalized, category: snap.category, updatedAt: snap.updatedAt)
                cloud.insert(row)
                byKey[snap.merchantNormalized] = row
            }
        }
        try? cloud.save()
    }
}
