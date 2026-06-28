import SwiftUI

/// 지출 저장 직후 그 카테고리의 예산 진행률을 잠깐 보여주는 토스트.
/// ContentView가 TabView.overlay로 띄우며, 표시/해제 애니메이션은 호출부가 관리한다.
struct BudgetToastView: View {
    let line: BudgetProgress.Line
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BudgetProgress.toastSummary(for: line))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            ProgressView(value: min(line.ratio, 1.0))
                .tint(line.state.tintColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(line.state.tintColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task {
            // 취소(연속 저장으로 토스트 교체 등) 시 onDismiss를 호출하면
            // 방금 뜬 다음 토스트를 닫아버리므로, 정상 만료일 때만 닫는다.
            guard (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BudgetProgress.toastSummary(for: line))
        .accessibilityHint("탭하면 닫혀요.")
    }
}
