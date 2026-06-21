import Foundation
import SwiftData

/// 예산 행의 값 스냅샷. 구 스토어(App Group)를 줄어든 스키마로 다시 열기 전에
/// 값으로 떠놓기 위한 구조체(모델 인스턴스가 아님).
struct BudgetSnapshot: Equatable {
    let category: String
    let monthlyLimit: Int
    let effectiveFrom: Int
    let updatedAt: Date
}

/// SavedEntry 값 스냅샷. 구 스토어를 줄어든 스키마로 다시 열기 전에 값으로 떠둔다.
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

/// 정산 헤더 값 스냅샷.
struct ReconciliationSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let note: String?
    let updatedAt: Date
}

/// 계좌 월별 잔액 값 스냅샷.
struct AccountBalanceSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let accountName: String
    let sortOrder: Int
    let openingBalance: Int
    let closingBalance: Int
    let interestAmount: Int
}

/// 자금 변동 값 스냅샷.
struct CashAdjustmentSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let title: String
    let direction: CashAdjustmentDirection
    let amount: Int
    let sortOrder: Int
    let note: String?
}

/// 수입·카드사용·저축 공용 라인 항목 값 스냅샷(세 모델의 필드 형태가 동일).
struct LineItemSnapshot: Equatable {
    let id: UUID
    let monthKey: Int
    let title: String
    let amount: Int
    let sortOrder: Int
    let updatedAt: Date
}

/// 가맹점→카테고리 학습 값 스냅샷.
struct MerchantSnapshot: Equatable {
    let merchantNormalized: String
    let category: String
    let updatedAt: Date
}

/// 기존 사용자의 예산·카테고리를 App Group 로컬 스토어 → CloudKit 스토어로 1회성 이전.
/// 모든 단계는 멱등(키 기준 upsert)이라 중간에 끊겨 재실행돼도 중복을 만들지 않는다.
enum CloudStoreMigration {
    /// 구 스토어의 모든 예산을 값 스냅샷으로 읽는다.
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

    /// 스냅샷을 CloudKit 스토어로 복사. `(category, effectiveFrom)` 키로 upsert.
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

    /// 카테고리 이름 배열을 `CategoryPreset` 레코드로 시드. 이름 키로 upsert, 인덱스를 `sortOrder`로.
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

    /// 구 스토어의 모든 지출을 값 스냅샷으로 읽는다.
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

    /// 스냅샷을 CloudKit 스토어로 복사. `id` 키로 upsert(재실행 멱등).
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

    // MARK: - 정산 헤더

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

    // MARK: - 계좌 월별 잔액

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

    // MARK: - 자금 변동

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

    // MARK: - 라인 항목(저축·카드사용·수입)

    @MainActor
    static func snapshotSavings(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<SavingsItem>())) ?? []
        return rows.map { LineItemSnapshot(id: $0.id, monthKey: $0.monthKey, title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt) }
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
                let row = SavingsItem(id: snap.id, monthKey: snap.monthKey, title: snap.title, amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt)
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    @MainActor
    static func snapshotCardUsage(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<CardUsageItem>())) ?? []
        return rows.map { LineItemSnapshot(id: $0.id, monthKey: $0.monthKey, title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt) }
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
                let row = CardUsageItem(id: snap.id, monthKey: snap.monthKey, title: snap.title, amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt)
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    @MainActor
    static func snapshotIncome(from source: ModelContext) -> [LineItemSnapshot] {
        let rows = (try? source.fetch(FetchDescriptor<IncomeItem>())) ?? []
        return rows.map { LineItemSnapshot(id: $0.id, monthKey: $0.monthKey, title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt) }
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
                let row = IncomeItem(id: snap.id, monthKey: snap.monthKey, title: snap.title, amount: snap.amount, sortOrder: snap.sortOrder, updatedAt: snap.updatedAt)
                cloud.insert(row); byID[snap.id] = row
            }
        }
        try? cloud.save()
    }

    // MARK: - 가맹점 카테고리 학습

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
