import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct CloudStoreMigrationTests {
    private func makeContext(_ types: [any PersistentModel.Type]) throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(types),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func makeContextWithAppSchema() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func snapshotReadsAllBudgets() throws {
        let source = try makeContext([CategoryBudget.self])
        source.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_606))
        source.insert(CategoryBudget(category: "카페", monthlyLimit: 50_000, effectiveFrom: 202_605))
        try source.save()

        let snaps = CloudStoreMigration.snapshotBudgets(from: source)
        #expect(snaps.count == 2)
        #expect(snaps.contains { $0.category == "식비" && $0.monthlyLimit == 300_000 && $0.effectiveFrom == 202_606 })
    }

    @Test func copyBudgetsIsIdempotent() throws {
        let cloud = try makeContext([CategoryBudget.self])
        let snaps = [
            BudgetSnapshot(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_606, updatedAt: .now),
        ]
        CloudStoreMigration.copyBudgets(snaps, into: cloud)
        CloudStoreMigration.copyBudgets(snaps, into: cloud) // 재실행해도 중복 없음
        let all = try cloud.fetch(FetchDescriptor<CategoryBudget>())
        #expect(all.count == 1)
        #expect(all.first?.monthlyLimit == 300_000)
    }

    @Test func seedPresetsCreatesOrderedRecords() throws {
        let cloud = try makeContext([CategoryPreset.self])
        CloudStoreMigration.seedPresets(["식비", "카페", "교통"], into: cloud)
        let sorted = try cloud.fetch(FetchDescriptor<CategoryPreset>()).sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted.map(\.name) == ["식비", "카페", "교통"])
        #expect(sorted.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func seedPresetsIsIdempotent() throws {
        let cloud = try makeContext([CategoryPreset.self])
        CloudStoreMigration.seedPresets(["식비", "카페"], into: cloud)
        CloudStoreMigration.seedPresets(["식비", "카페"], into: cloud)
        let all = try cloud.fetch(FetchDescriptor<CategoryPreset>())
        #expect(all.count == 2)
    }
}

@MainActor
@Suite struct CloudStoreMigrationEntriesTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func copiesEntriesIntoCloudStore() throws {
        let cloud = try makeContext()
        let snap = EntrySnapshot(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 5000, merchant: "스타벅스", category: "카페",
            note: nil, savedAt: Date(timeIntervalSince1970: 1_700_000_100),
            csvFile: "expenses-2023-11.csv"
        )
        CloudStoreMigration.copyEntries([snap], into: cloud)
        let rows = try cloud.fetch(FetchDescriptor<SavedEntry>())
        #expect(rows.count == 1)
        #expect(rows.first?.merchant == "스타벅스")
        #expect(rows.first?.amount == 5000)
    }

    @Test func copyEntriesIsIdempotentByID() throws {
        let cloud = try makeContext()
        let id = UUID()
        let snap = EntrySnapshot(
            id: id, date: .now, amount: 1000, merchant: "A",
            category: nil, note: nil, savedAt: .now, csvFile: "expenses-2026-06.csv"
        )
        CloudStoreMigration.copyEntries([snap], into: cloud)
        // 같은 id로 금액만 바꿔 재실행 → 중복 없이 업데이트.
        let updated = EntrySnapshot(
            id: id, date: snap.date, amount: 2000, merchant: "A",
            category: nil, note: nil, savedAt: snap.savedAt, csvFile: snap.csvFile
        )
        CloudStoreMigration.copyEntries([updated], into: cloud)
        let rows = try cloud.fetch(FetchDescriptor<SavedEntry>())
        #expect(rows.count == 1)
        #expect(rows.first?.amount == 2000)
    }

    @Test func snapshotEntriesReadsAllFields() throws {
        let source = try makeContext()
        source.insert(SavedEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 3000, merchant: "편의점", category: "간식",
            note: "할인", csvFile: "expenses-2023-11.csv"
        ))
        try source.save()
        let snaps = CloudStoreMigration.snapshotEntries(from: source)
        #expect(snaps.count == 1)
        #expect(snaps.first?.merchant == "편의점")
        #expect(snaps.first?.note == "할인")
    }
}
