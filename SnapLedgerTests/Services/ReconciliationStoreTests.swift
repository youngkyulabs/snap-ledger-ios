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

        // 기존 저장 데이터(2026-06)가 있다.
        context.insert(MonthlyReconciliation(monthKey: 202_606))
        context.insert(IncomeItem(monthKey: 202_606, title: "기존", amount: 111, sortOrder: 0))
        try context.save()

        // 폴더를 읽기 전용으로 만들어 CSV 쓰기를 실패시킨다.
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

        // CloudKit이 진실원 — CSV 쓰기 실패는 best-effort라 저장(DB)은 성공하고, export 실패만 false로 보고한다.
        let exported = try ReconciliationStore().save(draft, month: 202_606, in: context)
        #expect(exported == false)

        // DB는 새 값으로 갱신된다 (롤백 없음).
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

        // 전월 수입 항목이 이름·금액 그대로 이월된다.
        #expect(draft.incomes.map(\.amount).reduce(0, +) == 3_000_000)
        #expect(draft.incomes.first?.title == "월급")
        // 전월 카드는 이름만 이월되고 금액은 0으로 비운다(매월 변동).
        #expect(draft.cards.first?.title == "신한카드")
        #expect(draft.cards.map(\.amount).reduce(0, +) == 0)
        #expect(draft.savings.map(\.amount).reduce(0, +) == 500_000)
        #expect(draft.savings.first?.title == "적금")
        #expect(draft.balances.count == 1)
        #expect(draft.balances.first?.accountName == "입출금")
        // 전월 기말이 이번 달 기초로 이월되고, 이자는 0으로 초기화된다.
        #expect(draft.balances.first?.opening == 2_000_000)
        #expect(draft.balances.first?.closing == 2_000_000)
        #expect(draft.balances.first?.interest == 0)

        // 불러오기만으로는 이번 달(202606)에 아무것도 영속화되지 않아야 한다.
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

        // 다음 달은 비어 있으므로 카드 항목은 이름만 이월되고 금액은 0으로 비운다.
        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(draft.cards.map(\.title) == ["신한", "현대"])
        #expect(draft.cards.map(\.amount) == [0, 0])

        // 저장하면 카드 항목으로 영속화된다.
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

        // 다음 달은 비어 있으므로 수입 항목이 이름·금액 그대로 이월된다.
        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(draft.incomes.map(\.title) == ["월급", "보너스"])
        #expect(draft.incomes.map(\.amount) == [3_000_000, 500_000])

        // 저장하면 수입 항목으로 영속화된다.
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

        // 폴더 미설정이라 앱에만 저장되지만 DB 영속화·정렬은 동일하게 검증된다.
        try ReconciliationStore().save(draft, month: 202_606, in: context)

        // draft 배열 순서가 sortOrder로 보존돼 같은 순서로 다시 불러와진다 (이름순 자동정렬 아님).
        let reloaded = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(reloaded.adjustments.map(\.title) == ["환급", "전월 카드대금", "가족 송금"])

        // 첫 항목을 끝으로 옮긴 뒤 저장 → 새 순서가 그대로 보존된다.
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

        #expect(exported == false) // 폴더 미설정 → 앱에만 저장
        // 수입은 항목으로 영속화된다.
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
        // 이름·방향은 이월되고 금액은 0으로 비운다.
        #expect(draft.adjustments.map(\.title) == ["전월 카드대금", "환급"])
        #expect(draft.adjustments.map(\.direction) == [.withdrawal, .deposit])
        #expect(draft.adjustments.map(\.amount) == [0, 0])
    }
}
