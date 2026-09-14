import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct ReconciliationStoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: MonthlyReconciliation.self, AccountMonthlyBalance.self, CashAdjustment.self, SavingsItem.self,
            CardUsageItem.self, IncomeItem.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func saveKeepsNewDataWhenCSVWriteFails() throws {
        let context = try makeContext()

        // Existing saved data for 2026-06
        context.insert(MonthlyReconciliation(monthKey: 202_606))
        context.insert(IncomeItem(monthKey: 202_606, title: "기존", amount: 111, sortOrder: 0))
        try context.save()

        // Make folder read-only to trigger CSV write failure
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconReadonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        context.insert(AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: folder)))
        try context.save()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        var draft = ReconciliationDraft()
        draft.incomes = [IncomeItemDraft(title: "새값", amount: 999)]

        // Best-effort CSV export failure does not fail DB save
        let exported = try ReconciliationStore().save(draft, month: 202_606, in: context)
        #expect(exported == false)

        // Database remains updated without rollback
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>()).filter { $0.monthKey == 202_606 }
        #expect(incomes.count == 1)
        #expect(incomes.first?.title == "새값")
        #expect(incomes.first?.amount == 999)
    }

    @Test func loadDraftCarriesForwardPreviousMonthWithoutPersisting() throws {
        let context = try makeContext()
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000, sortOrder: 0))
        context.insert(CardUsageItem(monthKey: 202_605, title: "신한카드", amount: 450_000, sortOrder: 0))
        context.insert(SavingsItem(monthKey: 202_605, title: "적금", amount: 500_000))
        context.insert(
            AccountMonthlyBalance(
                monthKey: 202_605,
                accountName: "입출금",
                sortOrder: 0,
                openingBalance: 1_000_000,
                closingBalance: 2_000_000,
                interestAmount: 3_000
            )
        )
        try context.save()

        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)

        // Prior month income carried forward with title and amount
        #expect(draft.incomes.map(\.amount).reduce(0, +) == 3_000_000)
        #expect(draft.incomes.first?.title == "월급")
        // Prior month cards carried forward with title and 0 amount
        #expect(draft.cards.first?.title == "신한카드")
        #expect(draft.cards.map(\.amount).reduce(0, +) == 0)
        #expect(draft.savings.map(\.amount).reduce(0, +) == 500_000)
        #expect(draft.savings.first?.title == "적금")
        #expect(draft.balances.count == 1)
        #expect(draft.balances.first?.accountName == "입출금")
        // Closing balance carried forward as opening balance; interest reset to 0
        #expect(draft.balances.first?.opening == 2_000_000)
        #expect(draft.balances.first?.closing == 2_000_000)
        #expect(draft.balances.first?.interest == 0)

        // Draft load alone must not persist any entities
        let reconciliations = try context.fetch(FetchDescriptor<MonthlyReconciliation>())
        #expect(!reconciliations.contains { $0.monthKey == 202_606 })
        let balances = try context.fetch(FetchDescriptor<AccountMonthlyBalance>())
        #expect(!balances.contains { $0.monthKey == 202_606 })
        let savings = try context.fetch(FetchDescriptor<SavingsItem>())
        #expect(!savings.contains { $0.monthKey == 202_606 })
    }

    @Test func cardItemsCarryForwardAndPersistOnSave() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(CardUsageItem(monthKey: 202_605, title: "신한", amount: 300_000, sortOrder: 0))
        context.insert(CardUsageItem(monthKey: 202_605, title: "현대", amount: 200_000, sortOrder: 1))
        try context.save()

        // Next month cards prefilled with title and 0 amount
        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(draft.cards.map(\.title) == ["신한", "현대"])
        #expect(draft.cards.map(\.amount) == [0, 0])

        // Saving persists card items
        try ReconciliationStore().save(draft, month: 202_606, in: context)
        let cards = try context.fetch(FetchDescriptor<CardUsageItem>())
            .filter { $0.monthKey == 202_606 }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(cards.map(\.title) == ["신한", "현대"])
        #expect(cards.map(\.amount) == [0, 0])
    }

    @Test func incomeItemsCarryForwardAndPersistOnSave() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000, sortOrder: 0))
        context.insert(IncomeItem(monthKey: 202_605, title: "보너스", amount: 500_000, sortOrder: 1))
        try context.save()

        // Next month income prefilled with title and amount
        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(draft.incomes.map(\.title) == ["월급", "보너스"])
        #expect(draft.incomes.map(\.amount) == [3_000_000, 500_000])

        // Saving persists income items
        try ReconciliationStore().save(draft, month: 202_606, in: context)
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
            .filter { $0.monthKey == 202_606 }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(incomes.map(\.title) == ["월급", "보너스"])
        #expect(incomes.map(\.amount) == [3_000_000, 500_000])
    }

    @Test func adjustmentsPersistDraftOrderAndSurviveReorder() throws {
        let context = try makeContext()
        var draft = ReconciliationDraft()
        draft.adjustments = [
            AdjustmentDraft(title: "환급", direction: .deposit, amount: 30_000, note: nil, sortOrder: 0),
            AdjustmentDraft(title: "전월 카드대금", direction: .withdrawal, amount: 400_000, note: nil, sortOrder: 1),
            AdjustmentDraft(title: "가족 송금", direction: .deposit, amount: 50_000, note: nil, sortOrder: 2),
        ]

        // Unconfigured folder still tests persistence and ordering
        try ReconciliationStore().save(draft, month: 202_606, in: context)

        // Array order preserved via sortOrder
        let reloaded = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(reloaded.adjustments.map(\.title) == ["환급", "전월 카드대금", "가족 송금"])

        // Reordering items preserves updated order
        var moved = reloaded
        moved.adjustments.append(moved.adjustments.removeFirst())
        try ReconciliationStore().save(moved, month: 202_606, in: context)
        let after = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(after.adjustments.map(\.title) == ["전월 카드대금", "가족 송금", "환급"])
    }

    @Test func loadDraftReadsExistingMonth() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_606, note: "메모"))
        context.insert(IncomeItem(monthKey: 202_606, title: "월급", amount: 1))
        context.insert(AccountMonthlyBalance(monthKey: 202_606, accountName: "통장", openingBalance: 10))
        try context.save()

        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)

        #expect(draft.incomes.first?.amount == 1)
        #expect(draft.note == "메모")
        #expect(draft.balances.first?.opening == 10)
    }

    @Test func saveWithoutFolderPersistsToAppOnly() throws {
        let context = try makeContext()
        var draft = ReconciliationDraft()
        draft.incomes = [IncomeItemDraft(title: "월급", amount: 2_000_000)]
        draft.savings = [SavingsItemDraft(title: "청약", amount: 300_000)]
        draft.balances = [BalanceDraft(accountName: "통장", opening: 100, closing: 200)]

        let exported = try ReconciliationStore().save(draft, month: 202_606, in: context)

        #expect(exported == false) // Unconfigured folder -> app-only save
        // Income is persisted as IncomeItem
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
        #expect(incomes.first { $0.monthKey == 202_606 }?.amount == 2_000_000)
        let balances = try context.fetch(FetchDescriptor<AccountMonthlyBalance>())
        #expect(balances.first { $0.monthKey == 202_606 }?.closingBalance == 200)
        let savings = try context.fetch(FetchDescriptor<SavingsItem>())
        #expect(savings.first { $0.monthKey == 202_606 }?.title == "청약")
        #expect(savings.first { $0.monthKey == 202_606 }?.amount == 300_000)
    }

    @Test func saveEmptyDraftClearsExistingMonth() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_606))
        context.insert(AccountMonthlyBalance(monthKey: 202_606, accountName: "통장"))
        context.insert(SavingsItem(monthKey: 202_606, title: "적금", amount: 100))
        try context.save()

        try ReconciliationStore().save(ReconciliationDraft(), month: 202_606, in: context)

        let reconciliations = try context.fetch(FetchDescriptor<MonthlyReconciliation>())
        #expect(!reconciliations.contains { $0.monthKey == 202_606 })
        let balances = try context.fetch(FetchDescriptor<AccountMonthlyBalance>())
        #expect(!balances.contains { $0.monthKey == 202_606 })
        let savings = try context.fetch(FetchDescriptor<SavingsItem>())
        #expect(!savings.contains { $0.monthKey == 202_606 })
    }

    @Test func adjustmentsCarryForwardNamesAndDirectionWithZeroAmount() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(
            CashAdjustment(monthKey: 202_605, title: "전월 카드대금", direction: .withdrawal, amount: 400_000)
        )
        context.insert(
            CashAdjustment(monthKey: 202_605, title: "환급", direction: .deposit, amount: 100_000)
        )
        try context.save()

        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        // Titles and directions carried forward with 0 amount
        #expect(draft.adjustments.map(\.title) == ["전월 카드대금", "환급"])
        #expect(draft.adjustments.map(\.direction) == [.withdrawal, .deposit])
        #expect(draft.adjustments.map(\.amount) == [0, 0])
    }

    @Test func savingReconciliationAlsoExportsBudgetForThatMonth() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: [config]))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconBudgetExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        context.insert(AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir)))
        context.insert(CategoryBudget(category: "식비", monthlyLimit: 300_000, effectiveFrom: 202_605))
        try context.save()

        var draft = ReconciliationDraft()
        draft.incomes = [IncomeItemDraft(title: "월급", amount: 3_000_000)]
        let store = ReconciliationStore()
        try store.save(draft, month: 202_605, in: context)

        let budgetFile = dir.appendingPathComponent("budgets-2026-05.csv")
        #expect(FileManager.default.fileExists(atPath: budgetFile.path))
        let content = try String(contentsOf: budgetFile, encoding: .utf8)
        #expect(content.contains("식비,300000"))
    }
}
