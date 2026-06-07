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

    @State private var selectedMonthKey: Int?
    @State private var showingLimitEditor = false

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
            reconciliation: reconciliations.first { $0.monthKey == effectiveMonthKey },
            balances: accountBalances,
            adjustments: cashAdjustments,
            targetMonth: effectiveMonthKey
        )
    }

    var body: some View {
        NavigationStack {
            progressList
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
        }
    }

    // MARK: Display

    private var progressList: some View {
        List {
            reconciliationSection
            monthPickerSection
            if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                emptyBudgetSection
            } else {
                summarySection
            }
            if !summary.lines.isEmpty { linesSection }
            if !summary.unbudgeted.isEmpty { unbudgetedSection }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: effectiveMonthKey)
    }

    private var monthPickerSection: some View {
        Section {
            Picker("월 선택", selection: Binding(
                get: { effectiveMonthKey },
                set: { selectedMonthKey = $0 }
            )) {
                ForEach(availableMonthKeys, id: \.self) { key in
                    Text(Self.monthLabel(key)).tag(key)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var reconciliationSection: some View {
        Section {
            NavigationLink {
                MonthlyReconciliationView(month: effectiveMonthKey)
            } label: {
                ReconciliationSummaryRow(summary: reconciliationSummary)
            }
        } header: {
            Text("\(Self.monthLabel(effectiveMonthKey)) 정산").textCase(nil)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // 1줄: 사용액(실지출) — 헤드라인 숫자
                Text("\(summary.totalSpent.formatted(.number))원")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                if summary.totalLimit > 0 {
                    // 2줄: 예산(라벨) + 차액
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("예산 \(summary.totalLimit.formatted(.number))원")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        budgetRemainingLabel(remaining: summary.totalLimit - summary.totalSpent)
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
        } header: {
            Text(Self.monthLabel(summary.month)).textCase(nil)
        }
    }

    private var linesSection: some View {
        Section {
            ForEach(summary.lines) { line in LineRow(line: line, presets: presets) }
        } header: {
            Text("카테고리별 진행률").textCase(nil)
        }
    }

    private var unbudgetedSection: some View {
        Section {
            ForEach(summary.unbudgeted) { item in
                HStack {
                    Text(item.category).font(.body)
                    Spacer()
                    Text("\(item.spent.formatted(.number))원")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("한도를 정하지 않은 지출").textCase(nil)
        } footer: {
            Text("오른쪽 위 '한도 편집'에서 한도를 설정할 수 있어요.")
        }
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
    var comps = DateComponents()
    comps.year = key / 100
    comps.month = key % 100
    let cal = Calendar.current
    let date = cal.date(from: comps) ?? Date()
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy년 M월"
    return formatter.string(from: date)
}

private func budgetStateColor(_ state: BudgetProgress.State) -> Color {
    switch state {
    case .under: return .accentColor
    case .near: return .orange
    case .over: return .red
    }
}

@ViewBuilder
private func budgetRemainingLabel(remaining: Int) -> some View {
    if remaining >= 0 {
        Text("\(remaining.formatted(.number))원 남음")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    } else {
        Text("\((-remaining).formatted(.number))원 초과")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.red)
    }
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
            // 2줄: 예산(라벨) + 차액(항상 노출, 초과면 빨강)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("예산 \(line.limit.formatted(.number))원")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                budgetRemainingLabel(remaining: line.remaining)
            }
            // 3줄: 상태색 진행 바
            ProgressView(
                value: Double(min(line.spent, line.limit)),
                total: Double(max(line.limit, 1))
            )
            .tint(budgetStateColor(line.state))
        }
        .padding(.vertical, 2)
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

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var budgets: [CategoryBudget]

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }
    private var isCurrentMonth: Bool { month >= currentMonthKey }

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        TextField("0", text: limitText(for: category))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text("원").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("\(monthLabelText(month)) 한도").textCase(nil)
            } footer: {
                if isCurrentMonth {
                    Text("이번 달부터 적용되고, 이후 달에도 자동으로 반복돼요. 비워두면 한도가 없어요.")
                } else {
                    Text("이 달에만 적용돼요. 다른 달의 한도는 그대로 유지돼요.")
                }
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("한도 편집")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func limitText(for category: String) -> Binding<String> {
        Binding(
            get: {
                guard let limit = CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month) else {
                    return ""
                }
                return limit.formatted(.number)
            },
            set: { newValue in
                let amount = Int(newValue.filter(\.isNumber)) ?? 0
                let store = CategoryBudgetStore()
                if month < currentMonthKey {
                    // 과거 달: 그 달에만 적용 (이번 달·다른 달은 보존).
                    try? store.setLimitForSingleMonth(amount, for: category, month: month, in: modelContext)
                } else {
                    // 이번 달(이후 자동 반복).
                    try? store.setLimit(amount, for: category, effectiveFrom: month, in: modelContext)
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
            ],
            inMemory: true
        )
}
