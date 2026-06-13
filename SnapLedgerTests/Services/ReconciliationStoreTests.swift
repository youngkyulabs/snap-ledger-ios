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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func loadDraftCarriesForwardPreviousMonthWithoutPersisting() throws {
        let context = try makeContext()
        context.insert(
            MonthlyReconciliation(
                monthKey: 202_605,
                salaryAmount: 3_000_000,
                creditCardAmount: 450_000
            )
        )
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

        // 레거시 단일 월급 금액이 "월급" 한 항목으로 흡수되어 이월된다.
        #expect(draft.incomes.map(\.amount).reduce(0, +) == 3_000_000)
        #expect(draft.incomes.first?.title == "월급")
        // 레거시 단일 카드 금액이 한 항목으로 흡수되어 이월된다.
        #expect(draft.cards.map(\.amount).reduce(0, +) == 450_000)
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
        context.insert(MonthlyReconciliation(monthKey: 202_605, salaryAmount: 1))
        context.insert(CardUsageItem(monthKey: 202_605, title: "신한", amount: 300_000, sortOrder: 0))
        context.insert(CardUsageItem(monthKey: 202_605, title: "현대", amount: 200_000, sortOrder: 1))
        try context.save()

        // 다음 달은 비어 있으므로 카드 항목이 이름·금액 그대로 이월된다.
        let draft = ReconciliationStore().loadDraft(for: 202_606, in: context)
        #expect(draft.cards.map(\.title) == ["신한", "현대"])
        #expect(draft.cards.map(\.amount) == [300_000, 200_000])

        // 저장하면 항목으로 영속화되고, 레거시 단일 필드는 0으로 비워둔다.
        try ReconciliationStore().save(draft, month: 202_606, in: context)
        let cards = try context.fetch(FetchDescriptor<CardUsageItem>())
            .filter { $0.monthKey == 202_606 }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(cards.map(\.title) == ["신한", "현대"])
        #expect(cards.map(\.amount) == [300_000, 200_000])
        let reconciliation = try #require(
            try context.fetch(FetchDescriptor<MonthlyReconciliation>()).first { $0.monthKey == 202_606 }
        )
        #expect(reconciliation.creditCardAmount == 0)
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

        // 저장하면 항목으로 영속화되고, 레거시 단일 필드는 0으로 비워둔다.
        try ReconciliationStore().save(draft, month: 202_606, in: context)
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
            .filter { $0.monthKey == 202_606 }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(incomes.map(\.title) == ["월급", "보너스"])
        #expect(incomes.map(\.amount) == [3_000_000, 500_000])
        let reconciliation = try #require(
            try context.fetch(FetchDescriptor<MonthlyReconciliation>()).first { $0.monthKey == 202_606 }
        )
        #expect(reconciliation.salaryAmount == 0)
    }

    @Test func loadDraftReadsExistingMonth() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_606, salaryAmount: 1, note: "메모"))
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
        // 수입은 항목으로 영속화되고, 레거시 단일 salaryAmount는 0으로 비워둔다.
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>())
        #expect(incomes.first { $0.monthKey == 202_606 }?.amount == 2_000_000)
        let reconciliations = try context.fetch(FetchDescriptor<MonthlyReconciliation>())
        #expect(reconciliations.first { $0.monthKey == 202_606 }?.salaryAmount == 0)
        let balances = try context.fetch(FetchDescriptor<AccountMonthlyBalance>())
        #expect(balances.first { $0.monthKey == 202_606 }?.closingBalance == 200)
        let savings = try context.fetch(FetchDescriptor<SavingsItem>())
        #expect(savings.first { $0.monthKey == 202_606 }?.title == "청약")
        #expect(savings.first { $0.monthKey == 202_606 }?.amount == 300_000)
    }

    @Test func saveEmptyDraftClearsExistingMonth() throws {
        let context = try makeContext()
        context.insert(MonthlyReconciliation(monthKey: 202_606, salaryAmount: 5))
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
}
