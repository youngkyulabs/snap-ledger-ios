import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var settingsList: [AppSettings]

    @State private var selectedMonthKey: Int?
    @State private var isEditing = false

    private var currentMonthKey: Int { CategoryBudgetStore.monthKey(from: Date()) }
    private var effectiveMonthKey: Int { selectedMonthKey ?? currentMonthKey }
    private var isViewingCurrentMonth: Bool { effectiveMonthKey == currentMonthKey }

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

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    editList
                } else if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                    emptyState
                } else {
                    progressList
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isEditing)
            .navigationTitle("예산")
            .toolbar {
                if isViewingCurrentMonth {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isEditing ? "완료" : "편집") {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { isEditing.toggle() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Display

    private var progressList: some View {
        List {
            monthPickerSection
            summarySection
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

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.totalSpent.formatted(.number))원")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    if summary.totalLimit > 0 {
                        Text("/ \(summary.totalLimit.formatted(.number))원")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if summary.totalLimit > 0 {
                        budgetRemainingLabel(remaining: summary.totalLimit - summary.totalSpent)
                    }
                }
                if summary.totalLimit > 0 {
                    ProgressView(
                        value: Double(min(summary.totalSpent, summary.totalLimit)),
                        total: Double(max(summary.totalLimit, 1))
                    )
                    .tint(budgetStateColor(summary.overallState))
                }
                Text("한도 설정 \(summary.budgetedSpent.formatted(.number))원 · 미설정 \(summary.unbudgetedSpent.formatted(.number))원")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("카테고리별 진행").textCase(nil)
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
            Text("한도 미설정 지출").textCase(nil)
        } footer: {
            if isViewingCurrentMonth {
                Text("'편집'에서 한도를 설정할 수 있어요.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("예산이 없어요", systemImage: "wonsign.circle")
        } description: {
            Text("카테고리별 한도를 정하면 진행률을 보여드려요.")
        } actions: {
            if isViewingCurrentMonth {
                Button("예산 설정") {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { isEditing = true }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Edit (이번 달 기준)

    private var editList: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { category in
                    HStack {
                        Circle().fill(CategoryColor.color(for: category, presets: presets))
                            .frame(width: 8, height: 8)
                        Text(category)
                        Spacer()
                        TextField("0", value: limitBinding(for: category), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text("원").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("\(Self.monthLabel(currentMonthKey)) 한도").textCase(nil)
            } footer: {
                Text("이번 달부터 적용돼요. 0으로 두면 한도가 없어요. 과거 달 한도는 그대로 유지돼요.")
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    private func limitBinding(for category: String) -> Binding<Int> {
        Binding(
            get: { CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: currentMonthKey) ?? 0 },
            set: { newValue in
                try? CategoryBudgetStore().setLimit(max(0, newValue), for: category, effectiveFrom: currentMonthKey, in: modelContext)
            }
        )
    }

    // MARK: Helpers

    private static func monthLabel(_ key: Int) -> String {
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
}

// MARK: - File-private helpers

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
        Text("남은 \(remaining.formatted(.number))원")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    } else {
        Text("초과 \((-remaining).formatted(.number))원")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.red)
    }
}

// MARK: - Subviews

private struct LineRow: View {
    let line: BudgetProgress.Line
    let presets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(CategoryColor.color(for: line.category, presets: presets))
                    .frame(width: 8, height: 8)
                Text(line.category).font(.body)
                Spacer()
                Text("\(line.spent.formatted(.number)) · \(line.limit.formatted(.number))원")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(min(line.spent, line.limit)),
                total: Double(max(line.limit, 1))
            )
            .tint(budgetStateColor(line.state))
            HStack {
                Spacer()
                budgetRemainingLabel(remaining: line.remaining)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    BudgetView()
        .modelContainer(for: [SavedEntry.self, CategoryBudget.self, AppSettings.self], inMemory: true)
}
