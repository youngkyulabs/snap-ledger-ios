import SwiftUI

extension BudgetProgress.State {
    /// Status tint color for budget progress bars.
    var tintColor: Color {
        switch self {
        case .under: return .accentColor
        case .near: return .orange
        case .over: return .red
        }
    }
}

func budgetRemainingColor(_ state: BudgetProgress.State) -> Color {
    switch state {
    case .under: return .secondary
    case .near: return .orange
    case .over: return .red
    }
}

func budgetRemainingLabel(remaining: Int, ratio: Double, state: BudgetProgress.State) -> some View {
    Text(budgetRemainingText(remaining: remaining, ratio: ratio))
        .foregroundStyle(budgetRemainingColor(state))
        .lineLimit(1)
}

func budgetRemainingText(remaining: Int, ratio: Double) -> String {
    let percent = BudgetProgress.usagePercent(ratio: ratio)
    return remaining >= 0
        ? "\(percent)% · \(remaining.formatted(.number))원 남음"
        : "\(percent)% · \((-remaining).formatted(.number))원 초과"
}

func remainingAccessibilityText(remaining: Int, state: BudgetProgress.State) -> String {
    var text = remaining >= 0
        ? "\(remaining.formatted(.number))원 남음"
        : "\((-remaining).formatted(.number))원 초과"
    if state == .near { text += ", 한도 임박" }
    return text
}

func summaryAccessibilityText(_ summary: BudgetProgress.Summary) -> String {
    let spent = "\(summary.totalSpent.formatted(.number))원"
    let count = "\(summary.entryCount)건"
    guard summary.totalLimit > 0 else {
        return "\(ledgerMonthLabel(summary.month)) 사용액 \(spent), \(count)"
    }
    let base = "\(ledgerMonthLabel(summary.month)) 예산 \(summary.totalLimit.formatted(.number))원 중 \(spent) 사용, \(count)"
    let remaining = remainingAccessibilityText(
        remaining: summary.totalLimit - summary.totalSpent,
        state: summary.overallState
    )
    return "\(base), \(remaining)"
}

func lineAccessibilityText(_ line: BudgetProgress.Line) -> String {
    let base = "\(line.category), 예산 \(line.limit.formatted(.number))원 중 \(line.spent.formatted(.number))원 사용"
    return "\(base), \(remainingAccessibilityText(remaining: line.remaining, state: line.state))"
}

/// Per-category progress row shared by the category progress sheet.
struct BudgetLineRow: View {
    let line: BudgetProgress.Line
    let presets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row header: category name and spending
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
            // Subtitle: limit, usage percent, difference
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("예산 \(line.limit.formatted(.number))원")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                budgetRemainingLabel(remaining: line.remaining, ratio: line.ratio, state: line.state)
                    .font(.caption.monospacedDigit())
            }
            // Row progress bar
            ProgressView(
                value: Double(min(line.spent, line.limit)),
                total: Double(max(line.limit, 1))
            )
            .tint(line.state.tintColor)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lineAccessibilityText(line))
    }
}
