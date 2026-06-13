import SwiftUI
import SwiftData

struct MonthlyReconciliationView: View {
    let month: Int

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]

    @State private var draft = ReconciliationDraft()
    @State private var didLoad = false
    @State private var newAccountName = ""
    @State private var showingAccountPrompt = false
    @State private var newSavingsName = ""
    @State private var showingSavingsPrompt = false
    @State private var newCardName = ""
    @State private var showingCardPrompt = false
    @State private var showingAdjustmentEditor = false
    @State private var conflict: SyncConflict?
    @State private var resultMessage: String?
    @FocusState private var focusedField: Field?

    /// 키보드 내림 버튼 노출과 월급 마스킹 해제에 쓰는 포커스 식별자.
    private enum Field: Hashable {
        case salary
        case memo
        case card(UUID)
        case savings(UUID)
        case opening(UUID)
        case closing(UUID)
        case interest(UUID)
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
            explanationSection
            monthlyInputSection
            cardsSection
            savingsSection
            accountsSection
            adjustmentsSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if focusedField != nil {
                HStack {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .padding(4)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("키보드 닫기")
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
            }
        }
        .navigationTitle("월 정산")
        .navigationSubtitle(reconciliationMonthLabel(month))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Label("저장", systemImage: "square.and.arrow.down")
                }
            }
        }
        .task {
            guard !didLoad else { return }
            draft = ReconciliationStore().loadDraft(for: month, in: modelContext)
            didLoad = true
        }
        .alert("계좌 추가", isPresented: $showingAccountPrompt) {
            TextField("계좌명", text: $newAccountName)
            Button("추가") { addAccount() }
            Button("취소", role: .cancel) { newAccountName = "" }
        } message: {
            Text("정산에 포함할 통장 이름을 입력하세요.")
        }
        .alert("저축 항목 추가", isPresented: $showingSavingsPrompt) {
            TextField("항목명", text: $newSavingsName)
            Button("추가") { addSavings() }
            Button("취소", role: .cancel) { newSavingsName = "" }
        } message: {
            Text("적금·펀드 등 저축 항목 이름을 입력하세요.")
        }
        .alert("카드 추가", isPresented: $showingCardPrompt) {
            TextField("카드명", text: $newCardName)
            Button("추가") { addCard() }
            Button("취소", role: .cancel) { newCardName = "" }
        } message: {
            Text("정산에 포함할 카드 이름을 입력하세요.")
        }
        .sheet(isPresented: $showingAdjustmentEditor) {
            NavigationStack {
                CashAdjustmentEditor(month: month) { adjustment in
                    draft.adjustments.append(adjustment)
                    draft.adjustments.sort {
                        $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date
                    }
                }
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

    private var summarySection: some View {
        let verdict = summary.verdict(status: periodStatus)
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verdict.headline)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(verdictColor(verdict.tone))
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
            Text("대사 결과").textCase(nil)
        }
    }

    private var monthlyInputSection: some View {
        Section {
            salaryRow
            TextField("메모", text: $draft.note)
                .focused($focusedField, equals: .memo)
        } header: {
            Text("월 요약").textCase(nil)
        }
    }

    private var salaryRow: some View {
        HStack {
            Text("월급")
            Spacer()
            ZStack(alignment: .trailing) {
                TextField("0", text: amountText($draft.salary))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150)
                    .focused($focusedField, equals: .salary)
                    .opacity(focusedField == .salary ? 1 : 0)
                    .accessibilityLabel("월급")
                    // 마스킹 중에는 VoiceOver에서도 숨겨 금액이 읽히지 않게 한다 (시각 마스킹과 일관).
                    .accessibilityHidden(focusedField != .salary)
                if focusedField != .salary {
                    Button {
                        focusedField = .salary
                    } label: {
                        Text("••••")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("월급 보기")
                }
            }
            Text("원")
                .foregroundStyle(.secondary)
                .opacity(focusedField == .salary ? 1 : 0)
        }
    }

    private var cardsSection: some View {
        Section {
            ForEach($draft.cards) { $item in
                HStack {
                    TextField("항목", text: $item.title)
                    Spacer()
                    TextField("0", text: amountText($item.amount))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                        .focused($focusedField, equals: .card(item.id))
                    Text("원")
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { draft.cards.remove(atOffsets: $0) }
            Button {
                showingCardPrompt = true
            } label: {
                Label("카드 추가", systemImage: "plus.circle")
            }
        } header: {
            Text("카드 사용액").textCase(nil)
        } footer: {
            Text("카드별 이번 달 사용액을 항목으로 입력하세요.")
        }
    }

    private var savingsSection: some View {
        Section {
            ForEach($draft.savings) { $item in
                HStack {
                    TextField("항목", text: $item.title)
                    Spacer()
                    TextField("0", text: amountText($item.amount))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                        .focused($focusedField, equals: .savings(item.id))
                    Text("원")
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { draft.savings.remove(atOffsets: $0) }
            Button {
                showingSavingsPrompt = true
            } label: {
                Label("저축 항목 추가", systemImage: "plus.circle")
            }
        } header: {
            Text("저축").textCase(nil)
        } footer: {
            Text("적금·펀드처럼 이번 달에 모은 돈을 항목별로 입력하세요.")
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach($draft.balances) { $balance in
                VStack(alignment: .leading, spacing: 8) {
                    Text(balance.accountName)
                        .font(.subheadline.weight(.medium))
                    moneyField("기초 잔액", value: $balance.opening, field: .opening(balance.id))
                    moneyField("기말 잔액", value: $balance.closing, field: .closing(balance.id))
                    moneyField("이자", value: $balance.interest, field: .interest(balance.id))
                }
                .padding(.vertical, 2)
            }
            .onDelete { draft.balances.remove(atOffsets: $0) }
            Button {
                showingAccountPrompt = true
            } label: {
                Label("계좌 추가", systemImage: "plus.circle")
            }
        } header: {
            Text("계좌별 잔액").textCase(nil)
        }
    }

    private var adjustmentsSection: some View {
        Section {
            ForEach(draft.adjustments) { adjustment in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(adjustment.title.isEmpty ? "자금변동" : adjustment.title)
                        if let note = adjustment.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(adjustment.direction.label) \(adjustment.amount.formatted(.number))원")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(adjustment.direction == .deposit ? .green : .secondary)
                }
            }
            .onDelete { draft.adjustments.remove(atOffsets: $0) }
            Button {
                showingAdjustmentEditor = true
            } label: {
                Label("자금변동 추가", systemImage: "plus.circle")
            }
        } header: {
            Text("자금변동").textCase(nil)
        } footer: {
            Text("환급, 가족 송금, 전월 카드대금 출금처럼 이번 달 지출 기록과 직접 맞추면 안 되는 잔액 변화를 입력하세요.")
        }
    }

    private var explanationSection: some View {
        Section {
            LabeledContent("거래 내역") {
                Text("\(summary.recordedExpenseAmount.formatted(.number))원")
                    .monospacedDigit()
            }
            LabeledContent("저축액") {
                Text("\(summary.savingsAmount.formatted(.number))원")
                    .monospacedDigit()
            }
            LabeledContent("자금변동 순액") {
                Text("\(summary.adjustmentNetAmount.formatted(.number))원")
                    .monospacedDigit()
            }
        } header: {
            Text("계산 기준").textCase(nil)
        }
    }
}

extension MonthlyReconciliationView {
    private func moneyField(_ title: String, value: Binding<Int>, field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: amountText(value))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 150)
                .focused($focusedField, equals: field)
            Text("원")
                .foregroundStyle(.secondary)
        }
    }

    private func verdictColor(_ tone: ReconciliationVerdict.Tone) -> Color {
        switch tone {
        case .balanced: .green
        case .off: .orange
        case .inProgress: .secondary
        }
    }

    private func amountText(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: {
                value.wrappedValue == 0 ? "" : value.wrappedValue.formatted(.number)
            },
            set: { newValue in
                value.wrappedValue = Int(newValue.filter(\.isNumber)) ?? 0
            }
        )
    }

    private func addAccount() {
        let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (draft.balances.map(\.sortOrder).max() ?? -1) + 1
        draft.balances.append(BalanceDraft(accountName: trimmed, sortOrder: nextOrder))
        newAccountName = ""
    }

    private func addSavings() {
        let trimmed = newSavingsName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (draft.savings.map(\.sortOrder).max() ?? -1) + 1
        draft.savings.append(SavingsItemDraft(title: trimmed, amount: 0, sortOrder: nextOrder))
        newSavingsName = ""
    }

    private func addCard() {
        let trimmed = newCardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (draft.cards.map(\.sortOrder).max() ?? -1) + 1
        draft.cards.append(CardUsageItemDraft(title: trimmed, amount: 0, sortOrder: nextOrder))
        newCardName = ""
    }

    private func save(ignoringConflict: Bool = false) {
        do {
            let exported = try ReconciliationStore().save(
                draft,
                month: month,
                ignoringConflict: ignoringConflict,
                in: modelContext
            )
            resultMessage = exported
                ? "앱과 CSV 파일에 저장했어요."
                : "앱에 저장했어요. 저장 폴더를 설정하면 CSV로도 저장돼요."
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

private struct CashAdjustmentEditor: View {
    let month: Int
    let onAdd: (AdjustmentDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var direction: CashAdjustmentDirection = .deposit
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        List {
            Section {
                TextField("항목", text: $title)
                Picker("방향", selection: $direction) {
                    ForEach(CashAdjustmentDirection.allCases, id: \.self) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("금액", text: $amount)
                        .keyboardType(.numberPad)
                    Text("원")
                        .foregroundStyle(.secondary)
                }
                TextField("메모", text: $note)
            }
        }
        .navigationTitle("자금변동")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("추가") { add() }
                    .disabled((Int(amount.filter(\.isNumber)) ?? 0) <= 0)
            }
        }
    }

    private func add() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onAdd(
            AdjustmentDraft(
                date: ReconciliationStore.date(month: month),
                title: cleanTitle.isEmpty ? direction.label : cleanTitle,
                direction: direction,
                amount: Int(amount.filter(\.isNumber)) ?? 0,
                note: cleanNote.isEmpty ? nil : cleanNote
            )
        )
        dismiss()
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
            AppSettings.self,
        ],
        inMemory: true
    )
}
