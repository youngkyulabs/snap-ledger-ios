import SwiftUI

/// 지출 저장 직후 그 카테고리의 예산 진행률을 잠깐 보여주는 토스트.
/// ContentView가 TabView.overlay로 띄우며, 표시/해제 애니메이션은 호출부가 관리한다.
struct BudgetToastView: View {
    let line: BudgetProgress.Line
    let presets: [String]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 원=카테고리색, 바=상태색 — 예산 탭 LineRow와 동일한 색 구성.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(CategoryColor.color(for: line.category, presets: presets))
                    .frame(width: 8, height: 8)
                Text(BudgetProgress.toastSummary(for: line))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            ProgressView(value: min(line.ratio, 1.0))
                .tint(line.state.tintColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // iOS 26 Liquid Glass 캡슐. 틴트는 상태색을 옅게 깔아 진행 바와 한 톤으로 묶는다.
        .glassEffect(
            .regular.tint(line.state.tintColor.opacity(0.18)).interactive(),
            in: .capsule
        )
        .contentShape(.capsule)
        .onTapGesture { onDismiss() }
        .task {
            // 취소(연속 저장으로 토스트 교체 등) 시 onDismiss를 호출하면
            // 방금 뜬 다음 토스트를 닫아버리므로, 정상 만료일 때만 닫는다.
            guard (try? await Task.sleep(for: .seconds(3.0))) != nil else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BudgetProgress.toastSummary(for: line))
        .accessibilityHint("탭하면 닫혀요.")
    }
}
