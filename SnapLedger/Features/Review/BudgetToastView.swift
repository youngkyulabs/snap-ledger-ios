import SwiftUI

/// Budget threshold toast item.
struct BudgetToastItem: Identifiable {
    let id = UUID()
    let line: BudgetProgress.Line
}

/// Floating capsule toast view for budget threshold warnings.
struct BudgetToastView: View {
    let line: BudgetProgress.Line
    var onDismiss: () -> Void

    private var isOver: Bool { line.state == .over }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isOver ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(line.state.tintColor)
            Text(line.category)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(BudgetProgress.usagePercent(ratio: line.ratio))%")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(line.state.tintColor)
                .monospacedDigit()
            Text("· \(BudgetProgress.remainderText(for: line))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.07), radius: 4, y: 1)
        .contentShape(.capsule)
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BudgetProgress.toastSummary(for: line))
        .accessibilityHint("탭하면 닫혀요")
    }
}

private struct BudgetToastModifier: ViewModifier {
    @Binding var item: BudgetToastItem?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            // Floating overlay at the bottom
            .overlay(alignment: .bottom) {
                if let item {
                    BudgetToastView(line: item.line) { dismiss() }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Auto-dismiss timer after 4 seconds
            .task(id: item?.id) {
                guard item != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                dismiss()
            }
            // Reset toast when leaving the view
            .onDisappear { item = nil }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { item = nil }
    }
}

extension View {
    /// ViewModifier presenting a budget threshold toast.
    func budgetToast(_ item: Binding<BudgetToastItem?>, reduceMotion: Bool) -> some View {
        modifier(BudgetToastModifier(item: item, reduceMotion: reduceMotion))
    }
}
