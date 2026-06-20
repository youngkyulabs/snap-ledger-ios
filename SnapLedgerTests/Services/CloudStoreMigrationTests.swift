import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct CloudStoreMigrationTests {
    private func makeContext(_ types: [any PersistentModel.Type]) throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(types),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
