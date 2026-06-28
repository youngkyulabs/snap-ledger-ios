import SwiftUI

/// 검토 탭 예산 상태 스트립 한 건. 매번 새 id를 받아, 같은 라인을 다시 띄워도
/// `.task(id:)` 자동닫기 타이머가 현재 표시 항목에 새로 묶이도록 한다.
struct BudgetStripItem: Identifiable {
    let id = UUID()
    let line: BudgetProgress.Line
}

/// 저장 직후 예산 임계(near/over)를 검토 화면 위에 알리는 막대.
/// List 바깥(safeAreaInset)이라 @Query 제거 애니메이션과 얽히지 않는다.
struct BudgetStatusStrip: View {
    let line: BudgetProgress.Line
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: line.state == .over ? "exclamationmark.triangle.fill" : "chart.pie.fill")
                .font(.subheadline)
            Text(BudgetProgress.statusSummary(for: line))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(line.state.tintColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.state.tintColor.opacity(0.15), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
        .contentShape(.rect)
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityHint("탭하면 닫혀요")
    }
}

private struct BudgetStatusStripModifier: ViewModifier {
    @Binding var item: BudgetStripItem?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let item {
                    BudgetStatusStrip(line: item.line) { dismiss() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // 자동닫기 타이머를 현재 항목 id에 묶는다. 새 스트립이 뜨면 이전 타이머가
            // 취소되고(이전 타이머가 새 스트립을 닫지 않음) 새로 시작한다.
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
    /// 검토 탭 상단에 예산 임계 상태 스트립을 띄운다(item이 nil이면 숨김, 4초 후 자동닫기).
    func budgetStatusStrip(_ item: Binding<BudgetStripItem?>, reduceMotion: Bool) -> some View {
        modifier(BudgetStatusStripModifier(item: item, reduceMotion: reduceMotion))
    }
}
