import SwiftUI

/// 월 선택 행 — ◀ 현재 월(메뉴) ▶. 예산·통계 탭 공용.
/// 화살표 한 칸의 의미(달력 인접 vs 데이터 인접)는 호출부가 정한다.
struct MonthNavigationRow<Key: Hashable>: View {
    struct Option: Identifiable {
        let key: Key
        let title: String
        var id: Key { key }
    }

    let title: String
    let options: [Option]
    let canStepBackward: Bool
    let canStepForward: Bool
    let stepBackward: () -> Void
    let stepForward: () -> Void
    let select: (Key) -> Void

    var body: some View {
        HStack {
            Button(action: stepBackward) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(minWidth: 44, minHeight: 32)
            }
            .disabled(!canStepBackward)
            .accessibilityLabel("이전 달")

            Spacer()

            Menu {
                ForEach(options) { option in
                    Button(option.title) { select(option.key) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("월 선택")
            .accessibilityValue(title)

            Spacer()

            Button(action: stepForward) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .frame(minWidth: 44, minHeight: 32)
            }
            .disabled(!canStepForward)
            .accessibilityLabel("다음 달")
        }
        .buttonStyle(.borderless)
    }
}
