import SwiftUI
import SwiftData

/// Destination screens on the ledger navigation stack.
enum BudgetRoute: Hashable {
    case reconciliation(month: Int)
    case limitEdit(month: Int, focus: String?)
}

/// Reconciliation entry and overall budget progress sections of the ledger list.
struct BudgetSections: View {
    /// Month shown, supplied by the shared selector above the list.
    let month: Int
    @Binding var path: [BudgetRoute]
    /// Opens the per-category progress sheet.
    let openCategoryProgress: () -> Void

    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var budgets: [CategoryBudget]
    @Query private var reconciliations: [MonthlyReconciliation]
    @Query private var accountBalances: [AccountMonthlyBalance]
    @Query private var cashAdjustments: [CashAdjustment]
    @Query private var savingsItems: [SavingsItem]
    @Query private var cardUsageItems: [CardUsageItem]
    @Query private var incomeItems: [IncomeItem]

    private var summary: BudgetProgress.Summary {
        BudgetProgress.compute(entries: entries, budgets: budgets, targetMonth: month)
    }

    private var reconciliationSummary: ReconciliationSummary {
        ReconciliationSummary.compute(
            entries: entries,
            input: ReconciliationSummaryInput(
                reconciliation: reconciliations.first { $0.monthKey == month },
                balances: accountBalances,
                adjustments: cashAdjustments,
                savingsItems: savingsItems,
                cardItems: cardUsageItems,
                incomeItems: incomeItems
            ),
            targetMonth: month
        )
    }

    var body: some View {
        // Compute progress once per render.
        let summary = self.summary
        Group {
            reconciliationSection(reconciliationSummary)
            if summary.lines.isEmpty && summary.unbudgeted.isEmpty {
                emptyBudgetSection
            } else {
                overallSection(summary)
            }
        }
    }

    private func reconciliationSection(_ summary: ReconciliationSummary) -> some View {
        // Reconciliation verdict matching reconciliation screen.
        let status = ReconciliationSummary.periodStatus(month: month, today: Date())
        let isReconciled = summary.isReconciled(status: status)
        return Section {
            NavigationLink(value: BudgetRoute.reconciliation(month: month)) {
                ReconciliationSummaryRow(
                    summary: summary,
                    verdict: summary.displayVerdict(status: status, isReconciled: isReconciled),
                    displayedActual: isReconciled ? summary.actualSpending : 0
                )
            }
        } header: {
            Text("정산하기").textCase(nil)
        }
    }

    private func overallSection(_ summary: BudgetProgress.Summary) -> some View {
        Section {
            Button(action: openCategoryProgress) {
                HStack(spacing: 8) {
                    overallProgress(summary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            Text("전체 진행률").textCase(nil)
        } footer: {
            Text("누르면 카테고리별 진행률을 볼 수 있어요.")
        }
    }

    private func overallProgress(_ summary: BudgetProgress.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Headline: actual spending and entry count
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.totalSpent.formatted(.number))원")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer(minLength: 6)
                Text("\(summary.entryCount)건")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if summary.totalLimit > 0 {
                // Subtitle: limit, usage percent, difference
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
                // Progress bar
                ProgressView(
                    value: Double(min(summary.totalSpent, summary.totalLimit)),
                    total: Double(max(summary.totalLimit, 1))
                )
                .tint(summary.overallState.tintColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityText(summary))
    }

    /// Shown when the month has neither limits nor spending to break down.
    private var emptyBudgetSection: some View {
        Section {
            Button {
                path.append(.limitEdit(month: month, focus: nil))
            } label: {
                Label("카테고리별 한도 정하기", systemImage: "wonsign.circle")
            }
        } header: {
            Text("전체 진행률").textCase(nil)
        } footer: {
            Text("한도를 정하면 예산 진행률을 보여드려요.")
        }
    }
}

private struct ReconciliationSummaryRow: View {
    let summary: ReconciliationSummary
    let verdict: ReconciliationVerdict
    let displayedActual: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verdict.headline)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(verdict.tone.color)
                Spacer()
                Text(verdict.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                amountBlock(title: "실제 쓴 돈", amount: displayedActual)
                amountBlock(title: "기록한 돈", amount: summary.recordedSpending)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let amounts = "실제 쓴 돈 \(displayedActual.formatted(.number))원, 기록한 돈 \(summary.recordedSpending.formatted(.number))원"
        let detail = verdict.detail.isEmpty ? "" : "\(verdict.detail), "
        return "\(verdict.headline), \(detail)\(amounts)"
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
