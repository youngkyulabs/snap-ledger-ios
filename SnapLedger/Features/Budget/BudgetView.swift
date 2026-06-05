import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var settingsList: [AppSettings]

    @State private var selectedMonthKey: Int?

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

    var body: some View {
        NavigationStack {
            Group {
                if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                    emptyState
                } else {
                    progressList
                }
            }
            .navigationTitle("예산")
        }
    }

    // MARK: Display

    private var progressList: some View {
        List {
            monthPickerSection
            summarySection
            if !summary.lines.isEmpty { linesSection }
            if !summary.unbudgeted.isEmpty { unbudgetedSection }
            editEntrySection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: effectiveMonthKey)
    }

    private var editEntrySection: some View {
        Section {
            NavigationLink {
                BudgetEditView(month: effectiveMonthKey, currentMonthKey: currentMonthKey)
            } label: {
                Label("예산·카테고리 편집", systemImage: "square.and.pencil")
            }
        }
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
            Text("아래 '예산·카테고리 편집'에서 한도를 설정할 수 있어요.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("예산이 없어요", systemImage: "wonsign.circle")
        } description: {
            Text("카테고리별 한도를 정하면 진행률을 보여드려요.")
        } actions: {
            NavigationLink {
                BudgetEditView(month: effectiveMonthKey, currentMonthKey: currentMonthKey)
            } label: {
                Text("예산 설정")
            }
            .buttonStyle(.borderedProminent)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(CategoryColor.color(for: line.category, presets: presets))
                    .frame(width: 8, height: 8)
                Text(line.category).font(.body)
                Spacer()
                Text("\(line.spent.formatted(.number))원 / \(line.limit.formatted(.number))원")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(min(line.spent, line.limit)),
                total: Double(max(line.limit, 1))
            )
            .tint(budgetStateColor(line.state))
            // 여유(under) 상태에선 "지출 / 한도"로 충분 — 임박·초과일 때만 남음/초과를 강조.
            if line.state != .under {
                HStack {
                    Spacer()
                    budgetRemainingLabel(remaining: line.remaining)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit screen (예산 한도 + 카테고리)

private struct BudgetEditView: View {
    let month: Int
    let currentMonthKey: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @Query private var budgets: [CategoryBudget]
    @State private var newCategoryText = ""
    @FocusState private var addFieldFocused: Bool

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    private var presets: [String] { settings.categoryPresets }
    private var isCurrentMonth: Bool { month >= currentMonthKey }

    var body: some View {
        List {
            limitsSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("예산·카테고리 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !presets.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
    }

    private var limitsSection: some View {
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
            .onDelete(perform: deleteCategory)
            .onMove(perform: moveCategory)

            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(canAddCategory ? Color.accentColor : Color.secondary)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: canAddCategory)
                TextField("새 카테고리 추가", text: $newCategoryText)
                    .submitLabel(.done)
                    .focused($addFieldFocused)
                    .onSubmit(addCategory)
                if canAddCategory {
                    Button("추가", action: addCategory)
                        .buttonStyle(.borderless)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: canAddCategory)
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

    private var canAddCategory: Bool {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !presets.contains(trimmed)
    }

    private func addCategory() {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.categoryPresets.contains(trimmed) else {
            newCategoryText = ""
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.append(trimmed)
            try? modelContext.save()
            newCategoryText = ""
        }
    }

    private func deleteCategory(at offsets: IndexSet) {
        let removed = offsets.map { settings.categoryPresets[$0] }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.remove(atOffsets: offsets)
            try? modelContext.save()
        }
        // 삭제된 카테고리의 예산은 이번 달부터 해제(과거 한도는 보존).
        let store = CategoryBudgetStore()
        for category in removed {
            try? store.endBudget(for: category, asOf: currentMonthKey, in: modelContext)
        }
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.move(fromOffsets: source, toOffset: destination)
            try? modelContext.save()
        }
    }
}

#Preview {
    BudgetView()
        .modelContainer(for: [SavedEntry.self, CategoryBudget.self, AppSettings.self], inMemory: true)
}
