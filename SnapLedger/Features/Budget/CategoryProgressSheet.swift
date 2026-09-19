import SwiftUI
import SwiftData

/// Per-category budget progress, opened from the overall progress row.
struct CategoryProgressSheet: View {
    let month: Int

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var settingsList: [AppSettings]
    @State private var path: [Route] = []

    /// Destinations pushed inside the sheet's own stack.
    private enum Route: Hashable {
        case entries(category: String)
        case limitEdit(category: String?)
    }

    private var currentMonthKey: Int { CategoryBudgetStore.monthKey(from: Date()) }

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    private var summary: BudgetProgress.Summary {
        BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: month)
    }

    var body: some View {
        let summary = self.summary
        NavigationStack(path: $path) {
            List {
                if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                    emptySection
                } else {
                    if !summary.lines.isEmpty { linesSection(summary) }
                    if !summary.unbudgeted.isEmpty { unbudgetedSection(summary) }
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .navigationTitle("카테고리별 진행률")
            .navigationSubtitle(ledgerMonthLabel(month))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .entries(let category):
                    CategoryEntriesView(detail: CategoryEntriesDetail(category: category, monthKey: month))
                case .limitEdit(let category):
                    BudgetLimitEditView(
                        month: month,
                        currentMonthKey: currentMonthKey,
                        focusCategory: category
                    )
                }
            }
        }
    }

    private var emptySection: some View {
        Section {
            Text("이 달에는 보여드릴 진행률이 없어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func linesSection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            ForEach(summary.lines) { line in
                Button {
                    path.append(.entries(category: line.category))
                } label: {
                    BudgetLineRow(line: line, presets: presets)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("한도를 정한 지출").textCase(nil)
        } footer: {
            Text("카테고리를 누르면 항목을 볼 수 있어요.")
        }
    }

    private func unbudgetedSection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            ForEach(summary.unbudgeted) { item in
                Button {
                    path.append(.entries(category: item.category))
                } label: {
                    unbudgetedRow(item)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Only preset categories are eligible for limit editing.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if presets.contains(item.category) {
                        Button {
                            path.append(.limitEdit(category: item.category))
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
            Text("카테고리를 누르면 항목을 볼 수 있어요. 한도는 왼쪽으로 밀어서 정할 수 있어요.")
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
}
