import Foundation
import SwiftData
import SwiftUI

/// 검토 탭에서 자동 처리에 실패한 이미지를 썸네일과 함께 보여주는 섹션.
/// 행을 누르면 원본 사진을 띄운 수동 입력으로, 스와이프로 삭제·(에러 한정)다시 시도로 이어진다.
struct FailedImagesSection: View {
    let failed: [PendingImage]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualContext: FailedManualContext?
    @State private var retryUnavailable = false

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
        .sheet(item: $manualContext) { context in
            EntryEditorView(entry: context.entry, insertOnSave: true) {
                delete(context.pending)
            }
        }
        .alert("지금은 다시 시도할 수 없어요", isPresented: $retryUnavailable) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(AppleIntelligenceStatus.current.reviewTabMessage)
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
                    clearAll()
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func row(_ pending: PendingImage) -> some View {
        let retryable = PendingProcessor.isRetryable(failureMessage: pending.failureMessage)
        Button {
            startManualEntry(pending)
        } label: {
            FailedImageRow(filename: pending.filename, retryable: retryable)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    delete(pending)
                }
            } label: {
                Label("삭제", systemImage: "trash")
            }
            .tint(.red)
            if retryable {
                Button {
                    Task { await retry(pending) }
                } label: {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
        }
    }

    private func startManualEntry(_ pending: PendingImage) {
        manualContext = FailedManualContext(
            pending: pending,
            entry: ParsedEntry(
                date: .now,
                amount: 0,
                merchant: "",
                sourceImagePath: pending.filename,
                confidence: 1.0
            )
        )
    }

    private func delete(_ pending: PendingImage) {
        let url = AppGroup.inboxURL.appendingPathComponent(pending.filename)
        try? FileManager.default.removeItem(at: url)
        modelContext.delete(pending)
        try? modelContext.save()
    }

    private func clearAll() {
        for pending in failed {
            delete(pending)
        }
    }

    private func retry(_ pending: PendingImage) async {
        guard AppleIntelligenceStatus.current.isAvailable else {
            retryUnavailable = true
            return
        }
        pending.state = .queued
        pending.failureMessage = nil
        try? modelContext.save()
        await PendingProcessor.make(in: modelContext).drain(in: modelContext)
    }
}

/// 실패 이미지에서 수동 입력 시트를 띄울 때 원본 PendingImage 와 새 항목을 함께 들고 다닌다.
private struct FailedManualContext: Identifiable {
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
