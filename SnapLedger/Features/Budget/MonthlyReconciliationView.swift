import SwiftUI
import SwiftData

struct MonthlyReconciliationView: View {
    let month: Int

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]

    @State private var draft = ReconciliationDraft()
    @State private var didLoad = false
    @State private var activeSheet: ActiveSheet?
    /// 정산 결과를 제외한 금액(계좌별 잔액·수입·저축·카드·자금변동)을 가린다. 기본 가림.
    @State private var amountsHidden = true
    @State private var conflict: SyncConflict?
    @State private var resultMessage: String?

    /// 어떤 항목을 어떤 시트로 편집 중인지. 연관 값이 nil이면 새 항목 추가.
    private enum ActiveSheet: Identifiable {
        case account(BalanceDraft?)
        case income(IncomeItemDraft?)
        case savings(SavingsItemDraft?)
        case card(CardUsageItemDraft?)
        case adjustment(AdjustmentDraft?)

        var id: String {
            switch self {
            case .account(let item): "account-\(item?.id.uuidString ?? "new")"
            case .income(let item): "income-\(item?.id.uuidString ?? "new")"
            case .savings(let item): "savings-\(item?.id.uuidString ?? "new")"
            case .card(let item): "card-\(item?.id.uuidString ?? "new")"
            case .adjustment(let item): "adjustment-\(item?.id.uuidString ?? "new")"
            }
        }
    }

    private var summary: ReconciliationSummary {
        draft.summary(entries: entries, month: month)
    }

    private var periodStatus: ReconciliationPeriodStatus {
        ReconciliationSummary.periodStatus(month: month, today: Date())
    }

    var body: some View {
        List {
            summarySection
            accountsSection
            incomeSection
            savingsSection
            cardsSection
            adjustmentsSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle("월 정산")
        .navigationSubtitle(reconciliationMonthLabel(month))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    amountsHidden.toggle()
                } label: {
                    Label(
                        amountsHidden ? "금액 보기" : "금액 가리기",
                        systemImage: amountsHidden ? "eye.slash" : "eye"
                    )
                }
            }
        }
        .task {
            guard !didLoad else { return }
            draft = ReconciliationStore().loadDraft(for: month, in: modelContext)
            didLoad = true
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                editor(for: sheet)
            }
            .presentationDetents([.medium, .large])
        }
        .syncConflictAlert($conflict)
        .alert(
            "월 정산",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            ),
            presenting: resultMessage
        ) { _ in
            Button("확인", role: .cancel) { resultMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - 시트 라우팅

    @ViewBuilder
    private func editor(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .account(let existing):
            ReconciliationAccountEditor(initial: existing) { name, opening, closing, interest in
                saveAccount(existing: existing, name: name, opening: opening, closing: closing, interest: interest)
            }
        case .income(let existing):
            ReconciliationItemEditor(
                navTitle: existing == nil ? "수입 추가" : "수입 수정",
                titlePlaceholder: "항목",
                initialTitle: existing?.title ?? "",
                initialAmount: existing?.amount ?? 0
            ) { title, amount in
                saveIncome(existing: existing, title: title, amount: amount)
            }
        case .savings(let existing):
            ReconciliationItemEditor(
                navTitle: existing == nil ? "저축 항목 추가" : "저축 항목 수정",
                titlePlaceholder: "항목",
                initialTitle: existing?.title ?? "",
                initialAmount: existing?.amount ?? 0
            ) { title, amount in
                saveSavings(existing: existing, title: title, amount: amount)
            }
        case .card(let existing):
            ReconciliationItemEditor(
                navTitle: existing == nil ? "카드 추가" : "카드 수정",
                titlePlaceholder: "카드명",
                initialTitle: existing?.title ?? "",
                initialAmount: existing?.amount ?? 0
            ) { title, amount in
                saveCard(existing: existing, title: title, amount: amount)
            }
        case .adjustment(let existing):
            ReconciliationAdjustmentEditor(initial: existing) { title, direction, amount in
                saveAdjustment(existing: existing, title: title, direction: direction, amount: amount)
            }
        }
    }

    // MARK: - 섹션

    private var summarySection: some View {
        // 전월 값으로 프리필만 된(아직 저장 안 된) 달은 '아직 정산 전'으로 — 빈 DB를 읽는 예산 탭과
        // 결론이 어긋나지 않게 한다. 한 번이라도 편집해 저장하면 isCarriedForward가 풀려 실제 차이를 보여준다.
        let verdict = summary.displayVerdict(
            status: periodStatus,
            isReconciled: !draft.isCarriedForward && !draft.isEmpty,
            revealInProgressDifference: true
        )
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verdict.headline)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(verdict.tone.color)
                    Spacer()
                    Text(verdict.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("실제 쓴 돈") {
                    Text("\(summary.actualSpending.formatted(.number))원")
                        .monospacedDigit()
                }
                LabeledContent("기록한 돈") {
                    Text("\(summary.recordedSpending.formatted(.number))원")
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("정산 결과").textCase(nil)
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(draft.balances) { balance in
                Button {
                    activeSheet = .account(balance)
                } label: {
                    accountRow(balance)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.balances.remove(atOffsets: offsets)
                save()
            }
            addButton("계좌 추가") { activeSheet = .account(nil) }
        } header: {
            Text("계좌별 잔액").textCase(nil)
        }
    }

    private var incomeSection: some View {
        Section {
            ForEach(draft.incomes) { item in
                Button {
                    activeSheet = .income(item)
                } label: {
                    itemRow(title: item.title, amount: item.amount)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.incomes.remove(atOffsets: offsets)
                save()
            }
            addButton("수입 추가") { activeSheet = .income(nil) }
        } header: {
            Text("수입").textCase(nil)
        } footer: {
            Text("월급·보너스처럼 이번 달에 들어온 돈을 항목별로 입력하세요.")
        }
    }

    private var savingsSection: some View {
        Section {
            ForEach(draft.savings) { item in
                Button {
                    activeSheet = .savings(item)
                } label: {
                    itemRow(title: item.title, amount: item.amount)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.savings.remove(atOffsets: offsets)
                save()
            }
            addButton("저축 항목 추가") { activeSheet = .savings(nil) }
        } header: {
            Text("저축").textCase(nil)
        } footer: {
            Text("적금·펀드처럼 이번 달에 모은 돈을 항목별로 입력하세요.")
        }
    }

    private var cardsSection: some View {
        Section {
            ForEach(draft.cards) { item in
                Button {
                    activeSheet = .card(item)
                } label: {
                    itemRow(title: item.title, amount: item.amount)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.cards.remove(atOffsets: offsets)
                save()
            }
            addButton("카드 추가") { activeSheet = .card(nil) }
        } header: {
            Text("카드 사용액").textCase(nil)
        } footer: {
            Text("카드별 이번 달 사용액을 항목으로 입력하세요.")
        }
    }

    private var adjustmentsSection: some View {
        Section {
            ForEach(draft.adjustments) { adjustment in
                Button {
                    activeSheet = .adjustment(adjustment)
                } label: {
                    adjustmentRow(adjustment)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.adjustments.remove(atOffsets: offsets)
                save()
            }
            addButton("자금변동 추가") { activeSheet = .adjustment(nil) }
        } header: {
            Text("자금변동").textCase(nil)
        } footer: {
            Text("환급, 가족 송금, 전월 카드대금 출금처럼 이번 달 지출 기록과 직접 맞추면 안 되는 잔액 변화를 입력하세요.")
        }
    }

    // MARK: - 행

    private func accountRow(_ balance: BalanceDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(balance.accountName.isEmpty ? "계좌" : balance.accountName)
                    .font(.headline)
                Spacer(minLength: 8)
                if balance.interest != 0 {
                    Text("이자 \(maskedAmount(balance.interest))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                balanceColumn("월초 잔액", amount: balance.opening)
                balanceColumn("월말 잔액", amount: balance.closing)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private func balanceColumn(_ label: String, amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(maskedAmount(amount))
                .font(.callout.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemRow(title: String, amount: Int) -> some View {
        HStack {
            Text(title.isEmpty ? "항목" : title)
            Spacer()
            Text(maskedAmount(amount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private func adjustmentRow(_ adjustment: AdjustmentDraft) -> some View {
        HStack {
            Text(adjustment.title.isEmpty ? "자금변동" : adjustment.title)
            Spacer()
            Text("\(adjustment.direction.label) \(maskedAmount(adjustment.amount))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(adjustment.direction == .deposit ? .green : .secondary)
        }
        .contentShape(.rect)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle")
        }
    }

    private func maskedAmount(_ value: Int) -> String {
        amountsHidden ? "••••" : "\(value.formatted(.number))원"
    }
}

// MARK: - 업서트 + 저장

extension MonthlyReconciliationView {
    private func saveAccount(existing: BalanceDraft?, name: String, opening: Int, closing: Int, interest: Int) {
        if let existing, let index = draft.balances.firstIndex(where: { $0.id == existing.id }) {
            draft.balances[index].accountName = name
            draft.balances[index].opening = opening
            draft.balances[index].closing = closing
            draft.balances[index].interest = interest
        } else {
            let nextOrder = (draft.balances.map(\.sortOrder).max() ?? -1) + 1
            draft.balances.append(
                BalanceDraft(accountName: name, sortOrder: nextOrder, opening: opening, closing: closing, interest: interest)
            )
        }
        // 추가·수정한 금액을 바로 확인할 수 있도록 가리기를 해제한다.
        amountsHidden = false
        save()
    }

    private func saveIncome(existing: IncomeItemDraft?, title: String, amount: Int) {
        if let existing, let index = draft.incomes.firstIndex(where: { $0.id == existing.id }) {
            draft.incomes[index].title = title
            draft.incomes[index].amount = amount
        } else {
            let nextOrder = (draft.incomes.map(\.sortOrder).max() ?? -1) + 1
            draft.incomes.append(IncomeItemDraft(title: title, amount: amount, sortOrder: nextOrder))
        }
        amountsHidden = false
        save()
    }

    private func saveSavings(existing: SavingsItemDraft?, title: String, amount: Int) {
        if let existing, let index = draft.savings.firstIndex(where: { $0.id == existing.id }) {
            draft.savings[index].title = title
            draft.savings[index].amount = amount
        } else {
            let nextOrder = (draft.savings.map(\.sortOrder).max() ?? -1) + 1
            draft.savings.append(SavingsItemDraft(title: title, amount: amount, sortOrder: nextOrder))
        }
        amountsHidden = false
        save()
    }

    private func saveCard(existing: CardUsageItemDraft?, title: String, amount: Int) {
        if let existing, let index = draft.cards.firstIndex(where: { $0.id == existing.id }) {
            draft.cards[index].title = title
            draft.cards[index].amount = amount
        } else {
            let nextOrder = (draft.cards.map(\.sortOrder).max() ?? -1) + 1
            draft.cards.append(CardUsageItemDraft(title: title, amount: amount, sortOrder: nextOrder))
        }
        amountsHidden = false
        save()
    }

    private func saveAdjustment(
        existing: AdjustmentDraft?,
        title: String,
        direction: CashAdjustmentDirection,
        amount: Int
    ) {
        let resolvedTitle = title.isEmpty ? direction.label : title
        if let existing, let index = draft.adjustments.firstIndex(where: { $0.id == existing.id }) {
            draft.adjustments[index].title = resolvedTitle
            draft.adjustments[index].direction = direction
            draft.adjustments[index].amount = amount
        } else {
            draft.adjustments.append(
                AdjustmentDraft(
                    title: resolvedTitle,
                    direction: direction,
                    amount: amount,
                    note: nil
                )
            )
        }
        draft.adjustments.sort { $0.title < $1.title }
        amountsHidden = false
        save()
    }

    private func save(ignoringConflict: Bool = false) {
        // 한 번이라도 편집하면 더 이상 '이월 프리필'이 아니라 사용자가 확정하는 정산이다.
        draft.isCarriedForward = false
        do {
            // 편집할 때마다 조용히 자동 저장한다 (지출 기록과 동일). 성공 토스트는 띄우지 않는다.
            try ReconciliationStore().save(
                draft,
                month: month,
                ignoringConflict: ignoringConflict,
                in: modelContext
            )
        } catch ReconciliationStore.StoreError.externalConflict(let months) {
            conflict = SyncConflict(
                months: months,
                kind: .reconciliation,
                allowOverwrite: true,
                importDiscardsEdit: true
            ) { mode in
                switch mode {
                case .afterImport:
                    // 가져오기가 DB·파일을 이미 맞췄으니 편집 폼만 다시 읽어온다.
                    draft = ReconciliationStore().loadDraft(for: month, in: modelContext)
                    resultMessage = "파일 내용으로 맞췄어요."
                case .overwrite:
                    save(ignoringConflict: true)
                }
            }
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private func reconciliationMonthLabel(_ key: Int) -> String {
    var comps = DateComponents()
    comps.year = key / 100
    comps.month = key % 100
    let calendar = Calendar.current
    let date = calendar.date(from: comps) ?? Date()
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy년 M월"
    return formatter.string(from: date)
}

#Preview {
    NavigationStack {
        MonthlyReconciliationView(month: 202_606)
    }
    .modelContainer(
        for: [
            SavedEntry.self,
            MonthlyReconciliation.self,
            AccountMonthlyBalance.self,
            CashAdjustment.self,
            SavingsItem.self,
            CardUsageItem.self,
            IncomeItem.self,
            AppSettings.self,
        ],
        inMemory: true
    )
}
