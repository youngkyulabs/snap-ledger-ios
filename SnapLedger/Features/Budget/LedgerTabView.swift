import SwiftUI
import SwiftData

/// Hosts the budget and statistics panes under one shared month selection.
struct LedgerTabView: View {
    /// Signal from ContentView to reset selection back to the current month.
    var resetNonce: Int = 0

    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]

    @State private var selectedMonthKey: Int?
    @State private var pane: Pane = .budget
    @State private var path: [BudgetRoute] = []

    private enum Pane: String, CaseIterable, Identifiable {
        case budget = "예산"
        case statistics = "통계"

        var id: String { rawValue }
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
        // Restrict navigation to current month and earlier.
        return keys.filter { $0 <= currentMonthKey }.sorted(by: >)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                Divider()
                switch pane {
                case .budget:
                    BudgetView(month: effectiveMonthKey, path: $path)
                case .statistics:
                    StatisticsView(monthKey: effectiveMonthKey)
                }
            }
            .navigationTitle("예산")
            .toolbar {
                if pane == .budget {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            path.append(.limitEdit(month: effectiveMonthKey, focus: nil))
                        } label: {
                            Label("한도 편집", systemImage: "square.and.pencil")
                        }
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

    private var header: some View {
        VStack(spacing: 12) {
            MonthNavigationRow(
                title: ledgerMonthLabel(effectiveMonthKey),
                options: availableMonthKeys.map { .init(key: $0, title: ledgerMonthLabel($0)) },
                canStepBackward: effectiveMonthKey > (availableMonthKeys.min() ?? currentMonthKey),
                canStepForward: effectiveMonthKey < currentMonthKey,
                stepBackward: { selectedMonthKey = CategoryBudgetStore.previousMonthKey(effectiveMonthKey) },
                stepForward: { selectedMonthKey = CategoryBudgetStore.nextMonthKey(effectiveMonthKey) },
                select: { selectedMonthKey = $0 }
            )
            Picker("보기", selection: $pane) {
                ForEach(Pane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private func ledgerMonthLabel(_ key: Int) -> String {
    "\(key / 100)년 \(key % 100)월"
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
