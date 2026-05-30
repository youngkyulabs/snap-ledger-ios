import Foundation
import SwiftUI

/// 검토 탭에서 자동 처리에 실패한 이미지를 썸네일과 함께 보여주는 섹션.
/// 시트·얼럿 같은 프레젠테이션은 부모(ReviewListView)의 안정적인 레벨에서 처리하고,
/// 이 뷰는 표시와 사용자 의도(탭/삭제/재시도/모두 정리) 전달만 담당한다.
struct FailedImagesSection: View {
    let failed: [PendingImage]
    var onSelect: (PendingImage) -> Void
    var onDelete: (PendingImage) -> Void
    var onRetry: (PendingImage) -> Void
    var onClearAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            ForEach(failed) { pending in
                row(pending)
            }
        } header: {
            header
        } footer: {
            Text("사진을 누르면 직접 입력할 수 있어요. 잘못 들어온 이미지는 옆으로 밀어 삭제하세요.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("자동 처리되지 않은 이미지 \(failed.count)건")
                .contentTransition(.numericText())
            Spacer()
            Button("모두 정리") {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    onClearAll()
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func row(_ pending: PendingImage) -> some View {
        let retryable = PendingProcessor.isRetryable(failureMessage: pending.failureMessage)
        Button {
            onSelect(pending)
        } label: {
            FailedImageRow(filename: pending.filename, retryable: retryable)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    onDelete(pending)
                }
            } label: {
                Label("삭제", systemImage: "trash")
            }
            .tint(.red)
            if retryable {
                Button {
                    onRetry(pending)
                } label: {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
        }
    }
}

/// 실패 이미지에서 수동 입력 시트를 띄울 때 원본 PendingImage 와 새 항목을 함께 들고 다닌다.
struct FailedManualContext: Identifiable {
    let pending: PendingImage
    let entry: ParsedEntry
    var id: UUID { pending.id }
}

private struct FailedImageRow: View {
    let filename: String
    let retryable: Bool

    var body: some View {
        HStack(spacing: 12) {
            InboxThumbnail(filename: filename)
            VStack(alignment: .leading, spacing: 4) {
                Text(retryable ? "처리 중 문제가 생겼어요" : "결제 정보를 찾지 못했어요")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "square.and.pencil")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private var hint: String {
        retryable
            ? "눌러서 직접 입력하거나, 옆으로 밀어 다시 시도할 수 있어요."
            : "결제 화면 스크린샷이 맞는지 확인하세요. 눌러서 직접 입력할 수 있어요."
    }
}
