import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var settingsList: [AppSettings]
    @Query private var reconciliations: [MonthlyReconciliation]
    @Query private var accountBalances: [AccountMonthlyBalance]
    @Query private var cashAdjustments: [CashAdjustment]
    @Query private var savingsItems: [SavingsItem]

    @State private var selectedMonthKey: Int?
    @State private var showingLimitEditor = false
    @State private var categoryDetail: CategoryEntriesDetail?
    /// 한도 없는 지출 행의 스와이프 '한도 설정' → 해당 카테고리 포커스로 한도 편집 진입.
    @State private var limitEditCategory: String?

    private var currentMonthKey: Int { CategoryBudgetStore.monthKey(from: Date()) }
    private var effectiveMonthKey: Int { selectedMonthKey ?? currentMonthKey }

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    private var availableMonthKeys: [Int] {
        var keys: Set<Int> = [currentMonthKey]
        let cal = Calendar.current
        for entry in entries { keys.insert(CategoryBudgetStore.monthKey(from: entry.date, calendar: cal)) }
        for budget in budgets where budget.monthlyLimit > 0 { keys.insert(budget.effectiveFrom) }
        return keys.sorted(by: >)
    }

    private var summary: BudgetProgress.Summary {
        BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: effectiveMonthKey)
    }

    private var reconciliationSummary: ReconciliationSummary {
        ReconciliationSummary.compute(
            entries: entries,
            input: ReconciliationSummaryInput(
                reconciliation: reconciliations.first { $0.monthKey == effectiveMonthKey },
                balances: accountBalances,
                adjustments: cashAdjustments,
                savingsItems: savingsItems
            ),
            targetMonth: effectiveMonthKey
        )
    }

    var body: some View {
        // 집계는 전체 entries 순회라 비싸다 — 렌더링당 1회만 계산해 섹션에 넘긴다.
        let summary = self.summary
        let reconciliation = self.reconciliationSummary
        NavigationStack {
            progressList(summary: summary, reconciliation: reconciliation)
                .navigationTitle("예산")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingLimitEditor = true
                        } label: {
                            Label("한도 편집", systemImage: "square.and.pencil")
                        }
                    }
                }
                .navigationDestination(isPresented: $showingLimitEditor) {
                    BudgetLimitEditView(month: effectiveMonthKey, currentMonthKey: currentMonthKey)
                }
                .navigationDestination(item: $limitEditCategory) { category in
                    BudgetLimitEditView(
                        month: effectiveMonthKey,
                        currentMonthKey: currentMonthKey,
                        focusCategory: category
                    )
                }
        }
    }

    // MARK: Display

    private func progressList(summary: BudgetProgress.Summary, reconciliation: ReconciliationSummary) -> some View {
        List {
            monthPickerSection
            reconciliationSection(reconciliation)
            if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                emptyBudgetSection
            } else {
                summarySection(summary)
            }
            if !summary.lines.isEmpty { linesSection(summary) }
            if !summary.unbudgeted.isEmpty { unbudgetedSection(summary) }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: effectiveMonthKey)
        .sheet(item: $categoryDetail) { detail in
            CategoryEntriesSheet(detail: detail)
                .presentationDetents([.medium, .large])
        }
    }

    // 화살표는 달력 인접 이동 (한도는 매달 이어지므로 기록 없는 달도 의미가 있다).
    // 다음 달까지 허용 — 다음 달 예산을 미리 세팅하는 용도.
    private var monthPickerSection: some View {
        Section {
            MonthNavigationRow(
                title: Self.monthLabel(effectiveMonthKey),
                options: availableMonthKeys.map { .init(key: $0, title: Self.monthLabel($0)) },
                canStepBackward: effectiveMonthKey > (availableMonthKeys.min() ?? currentMonthKey),
                canStepForward: effectiveMonthKey < CategoryBudgetStore.nextMonthKey(currentMonthKey),
                stepBackward: { selectedMonthKey = CategoryBudgetStore.previousMonthKey(effectiveMonthKey) },
                stepForward: { selectedMonthKey = CategoryBudgetStore.nextMonthKey(effectiveMonthKey) },
                select: { selectedMonthKey = $0 }
            )
        }
    }

    private func reconciliationSection(_ summary: ReconciliationSummary) -> some View {
        Section {
            NavigationLink {
                MonthlyReconciliationView(month: effectiveMonthKey)
            } label: {
                ReconciliationSummaryRow(summary: summary)
            }
        } header: {
            Text("\(Self.monthLabel(effectiveMonthKey)) 정산").textCase(nil)
        }
    }

    private func summarySection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // 1줄: 사용액(실지출) — 헤드라인 숫자
                Text("\(summary.totalSpent.formatted(.number))원")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                if summary.totalLimit > 0 {
                    // 2줄: 예산(라벨) + 사용률·차액
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("예산 \(summary.totalLimit.formatted(.number))원")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        budgetRemainingLabel(
                            remaining: summary.totalLimit - summary.totalSpent,
                            ratio: summary.overallRatio,
                            state: summary.overallState
                        )
                        .font(.subheadline.monospacedDigit())
                    }
                    // 3줄: 진행 바
                    ProgressView(
                        value: Double(min(summary.totalSpent, summary.totalLimit)),
                        total: Double(max(summary.totalLimit, 1))
                    )
                    .tint(budgetStateColor(summary.overallState))
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summaryAccessibilityText(summary))
        } header: {
            Text(Self.monthLabel(summary.month)).textCase(nil)
        }
    }

    private func linesSection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            ForEach(summary.lines) { line in
                Button {
                    categoryDetail = CategoryEntriesDetail(category: line.category, monthKey: effectiveMonthKey)
                } label: {
                    LineRow(line: line, presets: presets)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("카테고리별 진행률").textCase(nil)
        } footer: {
            Text("카테고리를 누르면 항목을 볼 수 있어요.")
        }
    }

    private func unbudgetedSection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            ForEach(summary.unbudgeted) { item in
                Button {
                    categoryDetail = CategoryEntriesDetail(category: item.category, monthKey: effectiveMonthKey)
                } label: {
                    unbudgetedRow(item)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // 프리셋 카테고리만 한도 편집 진입 제공 (미분류 등은 한도 설정 대상이 아님).
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if presets.contains(item.category) {
                        Button {
                            limitEditCategory = item.category
                        } label: {
                            Label("한도 설정", systemImage: "wonsign.circle")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        } header: {
            Text("한도를 정하지 않은 지출").textCase(nil)
        } footer: {
            Text("카테고리를 누르면 항목을 볼 수 있어요. 한도는 왼쪽으로 밀거나 오른쪽 위 '한도 편집'에서 정할 수 있어요.")
        }
    }

    private func unbudgetedRow(_ item: BudgetProgress.Unbudgeted) -> some View {
        HStack {
            Text(item.category).font(.body)
            Spacer()
            Text("\(item.spent.formatted(.number))원")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyBudgetSection: some View {
        Section {
            Button {
                showingLimitEditor = true
            } label: {
                Label("카테고리별 한도 정하기", systemImage: "wonsign.circle")
            }
        } footer: {
            Text("한도를 정하면 예산 진행률을 보여드려요.")
        }
    }

    // MARK: Helpers

    private static func monthLabel(_ key: Int) -> String { monthLabelText(key) }
}

// MARK: - File-private helpers

private func monthLabelText(_ key: Int) -> String {
    "\(key / 100)년 \(key % 100)월"
}

private func budgetStateColor(_ state: BudgetProgress.State) -> Color {
    switch state {
    case .under: return .accentColor
    case .near: return .orange
    case .over: return .red
    }
}

private func budgetRemainingColor(_ state: BudgetProgress.State) -> Color {
    switch state {
    case .under: return .secondary
    case .near: return .orange
    case .over: return .red
    }
}

private func budgetRemainingLabel(remaining: Int, ratio: Double, state: BudgetProgress.State) -> some View {
    Text(budgetRemainingText(remaining: remaining, ratio: ratio))
        .foregroundStyle(budgetRemainingColor(state))
        .lineLimit(1)
}

private func budgetRemainingText(remaining: Int, ratio: Double) -> String {
    let percent = Int((ratio * 100).rounded())
    return remaining >= 0
        ? "\(percent)% · \(remaining.formatted(.number))원 남음"
        : "\(percent)% · \((-remaining).formatted(.number))원 초과"
}

private func remainingAccessibilityText(remaining: Int, state: BudgetProgress.State) -> String {
    var text = remaining >= 0
        ? "\(remaining.formatted(.number))원 남음"
        : "\((-remaining).formatted(.number))원 초과"
    if state == .near { text += ", 한도 임박" }
    return text
}

private func summaryAccessibilityText(_ summary: BudgetProgress.Summary) -> String {
    let spent = "\(summary.totalSpent.formatted(.number))원"
    guard summary.totalLimit > 0 else {
        return "\(monthLabelText(summary.month)) 사용액 \(spent)"
    }
    let base = "\(monthLabelText(summary.month)) 예산 \(summary.totalLimit.formatted(.number))원 중 \(spent) 사용"
    let remaining = remainingAccessibilityText(
        remaining: summary.totalLimit - summary.totalSpent,
        state: summary.overallState
    )
    return "\(base), \(remaining)"
}

private func lineAccessibilityText(_ line: BudgetProgress.Line) -> String {
    let base = "\(line.category), 예산 \(line.limit.formatted(.number))원 중 \(line.spent.formatted(.number))원 사용"
    return "\(base), \(remainingAccessibilityText(remaining: line.remaining, state: line.state))"
}

// MARK: - Subviews

private struct LineRow: View {
    let line: BudgetProgress.Line
    let presets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 1줄: 카테고리 이름 + 실지출(강조)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(CategoryColor.color(for: line.category, presets: presets))
                    .frame(width: 8, height: 8)
                Text(line.category)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(line.spent.formatted(.number))원")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            // 2줄: 예산(라벨) + 사용률·차액(상태색)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("예산 \(line.limit.formatted(.number))원")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                budgetRemainingLabel(remaining: line.remaining, ratio: line.ratio, state: line.state)
                    .font(.caption.monospacedDigit())
            }
            // 3줄: 상태색 진행 바
            ProgressView(
                value: Double(min(line.spent, line.limit)),
                total: Double(max(line.limit, 1))
            )
            .tint(budgetStateColor(line.state))
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lineAccessibilityText(line))
    }
}

private struct ReconciliationSummaryRow: View {
    let summary: ReconciliationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.hasReconciliationData ? "이번 달 정산" : "이번 달 정산을 시작하세요")
                    .font(.subheadline.weight(.medium))
                Spacer()
                differenceLabel
            }
            HStack(spacing: 12) {
                amountBlock(title: "실제 쓴 돈", amount: summary.actualSpending)
                amountBlock(title: "기록한 돈", amount: summary.recordedSpending)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let title = summary.hasReconciliationData ? "이번 달 정산" : "이번 달 정산을 시작하세요"
        let status = summary.isBalanced ? "정상" : "\(abs(summary.difference).formatted(.number))원 차이"
        let amounts = "실제 쓴 돈 \(summary.actualSpending.formatted(.number))원, 기록한 돈 \(summary.recordedSpending.formatted(.number))원"
        return "\(title), \(amounts), \(status)"
    }

    private var differenceLabel: some View {
        Group {
            if summary.isBalanced {
                Label("정상", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(abs(summary.difference).formatted(.number))원 차이")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.medium).monospacedDigit())
    }

    private func amountBlock(title: String, amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(amount.formatted(.number))원")
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Edit screen (예산 한도 전용)

private struct BudgetLimitEditView: View {
    let month: Int
    let currentMonthKey: Int
    var focusCategory: String?

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var budgets: [CategoryBudget]
    @FocusState private var focusedCategory: String?
    @State private var saveError: String?

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }
    private var isForwardMonth: Bool { month >= currentMonthKey }

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        TextField("0", value: limitValue(for: category), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .focused($focusedCategory, equals: category)
                        Text("원").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("\(monthLabelText(month)) 한도").textCase(nil)
            } footer: {
                if isForwardMonth {
                    Text("이 달부터 적용되고, 이후 달에도 자동으로 반복돼요. 비워두면 한도가 없어요.")
                } else {
                    Text("이 달에만 적용돼요. 다른 달의 한도는 그대로 유지돼요.")
                }
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if focusedCategory != nil {
                HStack {
                    Spacer()
                    Button {
                        focusedCategory = nil
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
        .navigationTitle("한도 편집")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedCategory = focusCategory }
        .alert(
            "저장 실패",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            ),
            presenting: saveError
        ) { _ in
            Button("확인", role: .cancel) { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    // 값 기반 TextField는 포커스가 떠날 때만 set을 호출하므로 저장은 편집당 1회.
    private func limitValue(for category: String) -> Binding<Int?> {
        Binding(
            get: { CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month) },
            set: { newValue in
                let amount = max(newValue ?? 0, 0)
                let current = CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month) ?? 0
                guard amount != current else { return }
                let store = CategoryBudgetStore()
                do {
                    if month < currentMonthKey {
                        // 과거 달: 그 달에만 적용 (이번 달·다른 달은 보존).
                        try store.setLimitForSingleMonth(amount, for: category, month: month, in: modelContext)
                    } else {
                        // 이번 달 이후: 이 달부터 자동 반복.
                        try store.setLimit(amount, for: category, effectiveFrom: month, in: modelContext)
                    }
                } catch {
                    saveError = "한도를 저장하지 못했어요. 다시 시도해주세요."
                }
            }
        )
    }
}

#Preview {
    BudgetView()
        .modelContainer(
            for: [
                SavedEntry.self,
                CategoryBudget.self,
                AppSettings.self,
                MonthlyReconciliation.self,
                AccountMonthlyBalance.self,
                CashAdjustment.self,
                SavingsItem.self,
            ],
            inMemory: true
        )
}
