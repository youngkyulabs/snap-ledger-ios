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
}
