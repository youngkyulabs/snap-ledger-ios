import SwiftUI

/// 검토 탭 예산 상태 토스트 한 건. 매번 새 id를 받아, 같은 라인을 다시 띄워도
/// `.task(id:)` 자동닫기 타이머가 현재 표시 항목에 새로 묶이도록 한다.
struct BudgetStripItem: Identifiable {
    let id = UUID()
    let line: BudgetProgress.Line
}

/// 저장 직후 예산 임계(near/over)를 알리는 하단 플로팅 캡슐 토스트.
/// 아이콘·퍼센트만 상태색(임박 주황 / 초과 빨강)으로 강조하고 나머지는 차분하게 둔다.
struct BudgetStatusStrip: View {
    let line: BudgetProgress.Line
    var onDismiss: () -> Void

    private var isOver: Bool { line.state == .over }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isOver ? "exclamationmark.triangle.fill" : "chart.pie.fill")
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
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .contentShape(.capsule)
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BudgetProgress.statusSummary(for: line))
        .accessibilityHint("탭하면 닫혀요")
    }
}

private struct BudgetStatusStripModifier: ViewModifier {
    @Binding var item: BudgetStripItem?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            // 리스트 위에 떠서 표시(overlay) — 레이아웃을 밀지 않아 저장 때마다 화면이 덜컹이지 않는다.
            .overlay(alignment: .bottom) {
                if let item {
                    BudgetStatusStrip(line: item.line) { dismiss() }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // 자동닫기 타이머를 현재 항목 id에 묶는다. 새 토스트가 뜨면 이전 타이머가
            // 취소되고(이전 타이머가 새 토스트를 닫지 않음) 새로 시작한다.
            .task(id: item?.id) {
                guard item != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { item = nil }
    }
}

extension View {
    /// 검토 탭 하단에 예산 임계 상태 토스트를 띄운다(item이 nil이면 숨김, 4초 후 자동닫기).
    func budgetStatusStrip(_ item: Binding<BudgetStripItem?>, reduceMotion: Bool) -> some View {
        modifier(BudgetStatusStripModifier(item: item, reduceMotion: reduceMotion))
    }
}
