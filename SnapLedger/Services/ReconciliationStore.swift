import Foundation
import SwiftData

/// 월 정산 편집 화면이 다루는 메모리 상태. 사용자가 "저장"하기 전까지는
/// DB·CSV에 아무것도 쓰지 않고 이 값만 들고 있다 (지출 입력 폼과 동일한 방식).
struct ReconciliationDraft: Equatable {
    var incomes: [IncomeItemDraft] = []
    var cards: [CardUsageItemDraft] = []
    var savings: [SavingsItemDraft] = []
    var note: String = ""
    var balances: [BalanceDraft] = []
    var adjustments: [AdjustmentDraft] = []

    /// 저장할 의미 있는 내용이 하나도 없으면 true (저장 시 그 달을 비운다).
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
    enum StoreError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case folderUnavailable
        case externalConflict(months: [String])
        case fileNotReady(months: [String])

        var errorDescription: String? {
            switch self {
            case .noCSVFolder:
                "저장 폴더가 설정되어 있지 않아 앱 안에만 저장했어요."
            case .bookmarkResolveFailed(let error):
                "폴더 권한을 복구하지 못했어요: \(error.localizedDescription)"
            case .folderUnavailable:
                "저장 폴더를 찾을 수 없어요. 설정 → 저장 폴더에서 다시 선택해 주세요."
            case .externalConflict(let months):
                "\(CSVWriter.monthLabels(months)) 정산 파일이 앱 밖에서 변경됐어요. 먼저 가져오거나 덮어쓸지 선택해 주세요."
            case .fileNotReady(let months):
                "\(CSVWriter.monthLabels(months)) 정산 파일을 아직 받아오는 중이에요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    // MARK: - 불러오기 (DB → 편집 폼)

    /// 그 달 편집 폼의 초기 상태를 만든다. 저장된 데이터가 있으면 그대로 읽고,
    /// 없으면 전월 값으로 미리 채운다. **어느 경우에도 DB에는 쓰지 않는다.**
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

    /// 전월 정산을 바탕으로 한 미리 채움 값 (영속화하지 않음). 잔액은 전월 월말을 이번 달 월초로 이월한다.
    private func carryForwardDraft(for month: Int, in context: ModelContext) -> ReconciliationDraft {
        let previous = Self.previousMonthKey(month)
        var draft = ReconciliationDraft()
        draft.incomes = incomeDrafts(items: fetchIncomes(previous, in: context))
        // 카드는 매월 변동하므로 이름만 이월하고 금액은 0으로 비운다.
        draft.cards = fetchCards(previous, in: context).map {
            CardUsageItemDraft(title: $0.title, amount: 0, sortOrder: $0.sortOrder)
        }
        // 자금변동도 이름·방향만 이월하고 금액은 0으로 비운다.
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

    /// 카드 항목을 draft로 변환한다.
    private func cardDrafts(items: [CardUsageItem]) -> [CardUsageItemDraft] {
        items.map { CardUsageItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder) }
    }

    /// 수입 항목을 draft로 변환한다.
    private func incomeDrafts(items: [IncomeItem]) -> [IncomeItemDraft] {
        items.map { IncomeItemDraft(title: $0.title, amount: $0.amount, sortOrder: $0.sortOrder) }
    }

    // MARK: - 저장 (편집 폼 → DB + CSV)

    /// 지출 저장(`SaveCoordinator`)과 동일한 흐름:
    /// 한 폴더 트랜잭션 안에서 외부 변경 가드 → 파일 기록 → DB 반영 → 지문 갱신을 함께 한다.
    /// 폴더가 없으면 앱에만 저장하고 `false`를 돌려준다.
    @discardableResult
    func save(
        _ draft: ReconciliationDraft,
        month: Int,
        ignoringConflict: Bool = false,
        in context: ModelContext
    ) throws -> Bool {
        do {
            try withFolder(in: context) { folderURL in
                let key = Self.monthString(from: month)
                if !ignoringConflict {
                    try ensureNoConflict(key: key, folderURL: folderURL, in: context)
                }
                replaceMonth(month, with: draft, in: context)
                do {
                    try SyncCoordinator().exportReconciliationMonths([key], folderURL: folderURL, in: context)
                    try context.save()
                } catch {
                    // CSV 쓰기/저장 실패 시 replaceMonth의 미커밋 insert/delete를 되돌려, DB만 바뀌고
                    // 파일은 그대로인 "감지 불가능한 어긋남"을 막는다 (SaveCoordinator와 동일).
                    context.rollback()
                    throw error
                }
            }
            return true
        } catch StoreError.noCSVFolder {
            // 폴더 미설정 — 앱에만 저장한다.
            replaceMonth(month, with: draft, in: context)
            try context.save()
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

    /// 그 달의 정산·잔액·자금변동 레코드를 모두 지운다. import 교체에서도 공용으로 쓴다.
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

    // MARK: - 내부

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

    private func ensureNoConflict(key: String, folderURL: URL, in context: ModelContext) throws {
        switch SyncCoordinator().checkWriteGuard(monthKeys: [key], kind: .reconciliation, folderURL: folderURL, in: context) {
        case .clear:
            return
        case .notReady(let keys):
            throw StoreError.fileNotReady(months: keys)
        case .conflict(let keys):
            throw StoreError.externalConflict(months: keys)
        }
    }
}

// MARK: - Fetch / 폴더 헬퍼

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

    private func withFolder<T>(
        in context: ModelContext,
        _ body: (URL) throws -> T
    ) throws -> T {
        do {
            return try CSVFolderAccess.withFolder(in: context, body)
        } catch let error as CSVFolderAccess.AccessError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: CSVFolderAccess.AccessError) -> StoreError {
        switch error {
        case .noCSVFolder: .noCSVFolder
        case .bookmarkResolveFailed(let underlying): .bookmarkResolveFailed(underlying: underlying)
        case .folderUnavailable: .folderUnavailable
        }
    }
}

extension ReconciliationDraft {
    /// 편집 중인 (아직 저장 안 된) 값으로 정산 요약을 계산한다. 임시 모델 인스턴스를 만들어
    /// `ReconciliationSummary.compute`에 넘긴다 (context에 삽입하지 않으므로 영속화되지 않는다).
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
