import SwiftUI
import SwiftData

/// Hosts the ledger tab: one scrolling list of reconciliation, budget, and statistics sections.
struct LedgerTabView: View {
    /// Signal from ContentView to reset selection back to the current month.
    var resetNonce: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var reconciliations: [MonthlyReconciliation]

    @State private var selectedMonthKey: Int?
    @State private var path: [BudgetRoute] = []
    @State private var sheet: LedgerSheet?

    /// Drill-down sheets opened from the ledger list.
    private enum LedgerSheet: Identifiable {
        case categoryProgress(month: Int)
        case categoryTotals(month: Int)

        var id: String {
            switch self {
            case .categoryProgress(let month): return "progress-\(month)"
            case .categoryTotals(let month): return "totals-\(month)"
            }
        }
    }

    private var currentMonthKey: Int { CategoryBudgetStore.monthKey(from: Date()) }
    private var effectiveMonthKey: Int { selectedMonthKey ?? currentMonthKey }

    private var availableMonthKeys: [Int] {
        var keys: Set<Int> = [currentMonthKey]
        let calendar = Calendar.current
        for entry in entries {
            keys.insert(CategoryBudgetStore.monthKey(from: entry.date, calendar: calendar))
        }
        for budget in budgets where budget.monthlyLimit > 0 { keys.insert(budget.effectiveFrom) }
        // A month may hold reconciliation data without any saved entry or limit.
        for reconciliation in reconciliations { keys.insert(reconciliation.monthKey) }
        // Restrict navigation to current month and earlier.
        return keys.filter { $0 <= currentMonthKey }.sorted(by: >)
    }

    /// Whether the selected month holds any spending or reconciliation data.
    private var hasRecords: Bool {
        let calendar = Calendar.current
        let hasEntries = entries.contains {
            CategoryBudgetStore.monthKey(from: $0.date, calendar: calendar) == effectiveMonthKey
        }
        return hasEntries || reconciliations.contains { $0.monthKey == effectiveMonthKey }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ledgerList
                .navigationTitle("월간 요약")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            path.append(.limitEdit(month: effectiveMonthKey, focus: nil))
                        } label: {
                            Label("한도 편집", systemImage: "square.and.pencil")
                        }
                    }
                }
                .navigationDestination(for: BudgetRoute.self) { route in
                    switch route {
                    case .reconciliation(let month):
                        MonthlyReconciliationView(month: month)
                    case .limitEdit(let month, let focus):
                        BudgetLimitEditView(
                            month: month,
                            currentMonthKey: currentMonthKey,
                            focusCategory: focus
                        )
                    }
                }
        }
        // Handle tab re-selection: pop to root or reset to the current month.
        .onChange(of: resetNonce) { _, _ in
            if path.isEmpty {
                selectedMonthKey = nil
            } else {
                path.removeAll()
            }
        }
    }

    private var ledgerList: some View {
        List {
            monthPickerSection
            if hasRecords {
                BudgetSections(month: effectiveMonthKey, path: $path) {
                    sheet = .categoryProgress(month: effectiveMonthKey)
                }
                StatisticsSections(month: effectiveMonthKey) {
                    sheet = .categoryTotals(month: effectiveMonthKey)
                }
            } else {
                emptyMonthSection
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: effectiveMonthKey)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .categoryProgress(let month):
                CategoryProgressSheet(month: month)
                    .presentationDetents([.medium, .large])
            case .categoryTotals(let month):
                CategoryTotalsSheet(month: month)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // Calendar month navigation bounded by the current month.
    private var monthPickerSection: some View {
        Section {
            MonthNavigationRow(
                title: ledgerMonthLabel(effectiveMonthKey),
                options: availableMonthKeys.map { .init(key: $0, title: ledgerMonthLabel($0)) },
                canStepBackward: effectiveMonthKey > (availableMonthKeys.min() ?? currentMonthKey),
                canStepForward: effectiveMonthKey < currentMonthKey,
                stepBackward: { selectedMonthKey = CategoryBudgetStore.previousMonthKey(effectiveMonthKey) },
                stepForward: { selectedMonthKey = CategoryBudgetStore.nextMonthKey(effectiveMonthKey) },
                select: { selectedMonthKey = $0 }
            )
        }
    }

    /// Months without saved entries or reconciliation data show nothing but this notice.
    private var emptyMonthSection: some View {
        Section {
            ContentUnavailableView(
                "기록 없음",
                systemImage: "list.bullet.rectangle",
                description: Text("이 달에는 기록이 없어요.")
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

#Preview {
    LedgerTabView()
        .modelContainer(
            for: [
                SavedEntry.self,
                CategoryBudget.self,
                AppSettings.self,
                MonthlyReconciliation.self,
                AccountMonthlyBalance.self,
                CashAdjustment.self,
                SavingsItem.self,
                CardUsageItem.self,
                IncomeItem.self,
            ],
            inMemory: true
        )
}
