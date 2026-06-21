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

@MainActor
@Suite struct CloudStoreMigrationReconciliationTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func copiesAllReconciliationModels() throws {
        let cloud = try makeContext()
        CloudStoreMigration.copyReconciliations(
            [ReconciliationSnapshot(id: UUID(), monthKey: 202_606, note: "메모", updatedAt: .now)], into: cloud)
        CloudStoreMigration.copyAccountBalances(
            [AccountBalanceSnapshot(id: UUID(), monthKey: 202_606, accountName: "주거래",
                                    sortOrder: 0, openingBalance: 100, closingBalance: 200, interestAmount: 5)], into: cloud)
        CloudStoreMigration.copyCashAdjustments(
            [CashAdjustmentSnapshot(id: UUID(), monthKey: 202_606, title: "환급",
                                    direction: .deposit, amount: 3000, sortOrder: 0, note: nil)], into: cloud)
        CloudStoreMigration.copySavings(
            [LineItemSnapshot(id: UUID(), monthKey: 202_606, title: "적금", amount: 100_000, sortOrder: 0, updatedAt: .now)], into: cloud)
        CloudStoreMigration.copyCardUsage(
            [LineItemSnapshot(id: UUID(), monthKey: 202_606, title: "신용카드", amount: 250_000, sortOrder: 0, updatedAt: .now)], into: cloud)
        CloudStoreMigration.copyIncome(
            [LineItemSnapshot(id: UUID(), monthKey: 202_606, title: "급여", amount: 3_000_000, sortOrder: 0, updatedAt: .now)], into: cloud)

        #expect(try cloud.fetch(FetchDescriptor<MonthlyReconciliation>()).count == 1)
        #expect(try cloud.fetch(FetchDescriptor<AccountMonthlyBalance>()).first?.interestAmount == 5)
        #expect(try cloud.fetch(FetchDescriptor<CashAdjustment>()).first?.direction == .deposit)
        #expect(try cloud.fetch(FetchDescriptor<SavingsItem>()).first?.amount == 100_000)
        #expect(try cloud.fetch(FetchDescriptor<CardUsageItem>()).first?.amount == 250_000)
        #expect(try cloud.fetch(FetchDescriptor<IncomeItem>()).first?.amount == 3_000_000)
    }

    @Test func copyReconciliationIsIdempotentByID() throws {
        let cloud = try makeContext()
        let id = UUID()
        CloudStoreMigration.copyReconciliations(
            [ReconciliationSnapshot(id: id, monthKey: 202_606, note: "v1", updatedAt: .now)], into: cloud)
        CloudStoreMigration.copyReconciliations(
            [ReconciliationSnapshot(id: id, monthKey: 202_606, note: "v2", updatedAt: .now)], into: cloud)
        let rows = try cloud.fetch(FetchDescriptor<MonthlyReconciliation>())
        #expect(rows.count == 1)
        #expect(rows.first?.note == "v2")
    }

    @Test func snapshotReadsReconciliationFields() throws {
        let source = try makeContext()
        source.insert(MonthlyReconciliation(monthKey: 202_606, note: "원본"))
        source.insert(IncomeItem(monthKey: 202_606, title: "급여", amount: 100, sortOrder: 1))
        try source.save()
        #expect(CloudStoreMigration.snapshotReconciliations(from: source).first?.note == "원본")
        #expect(CloudStoreMigration.snapshotIncome(from: source).first?.title == "급여")
    }
}

@MainActor
@Suite struct CloudStoreMigrationMerchantTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func copyMerchantsIsIdempotentByNormalized() throws {
        let cloud = try makeContext()
        CloudStoreMigration.copyMerchants(
            [MerchantSnapshot(merchantNormalized: "스타벅스", category: "카페", updatedAt: .now)], into: cloud)
        CloudStoreMigration.copyMerchants(
            [MerchantSnapshot(merchantNormalized: "스타벅스", category: "간식", updatedAt: .now)], into: cloud)
        let rows = try cloud.fetch(FetchDescriptor<MerchantCategory>())
        #expect(rows.count == 1)
        #expect(rows.first?.category == "간식")
    }

    @Test func snapshotMerchantsReadsAll() throws {
        let source = try makeContext()
        source.insert(MerchantCategory(merchantNormalized: "편의점", category: "간식"))
        try source.save()
        let snaps = CloudStoreMigration.snapshotMerchants(from: source)
        #expect(snaps.first?.merchantNormalized == "편의점")
        #expect(snaps.first?.category == "간식")
    }
}
