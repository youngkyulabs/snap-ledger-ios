import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct DroppedImage: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            DroppedImage(data: data)
        }
    }
}

struct ReviewListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ParsedEntry.createdAt, order: .reverse) private var allEntries: [ParsedEntry]
    @Query(sort: \PendingImage.receivedAt, order: .reverse) private var allPending: [PendingImage]
    @State private var editingEntry: ParsedEntry?
    @State private var manualEntry: ParsedEntry?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var importError: String?
    @State private var isDropTargeted = false
    @State private var pendingToDelete: ParsedEntry?
    @State private var swipeError: String?

    private var pendingEntries: [ParsedEntry] {
        allEntries.filter { $0.status == .pending }
    }

    private var processingPending: [PendingImage] {
        allPending.filter { $0.state == .queued || $0.state == .processing }
    }

    private var failedPending: [PendingImage] {
        allPending.filter { $0.state == .failed }
    }

    private var isFMAvailable: Bool {
        FoundationModelsExtractionService.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                if pendingEntries.isEmpty && processingPending.isEmpty && failedPending.isEmpty {
                    emptyState
                } else {
                    List {
                        if !isFMAvailable {
                            Section {
                                fmUnavailableBanner
                            }
                        }
                        if !processingPending.isEmpty {
                            Section {
                                processingRow
                            }
                        }
                        if !failedPending.isEmpty {
                            Section {
                                failedPendingRow
                            }
                        }
                        if !pendingEntries.isEmpty {
                            Section {
                                ForEach(pendingEntries) { entry in
                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        EntryRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        // role: .destructive를 쓰면 SwiftUI가 자동으로
                                        // ForEach row를 제거하려 하는데 @Query가 entry를
                                        // 그대로 들고 있어 깜빡이며 다시 등장한다. tint로
                                        // 색만 빨강으로 주고 role은 지정하지 않는다.
                                        Button {
                                            pendingToDelete = entry
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                        .tint(.red)
                                        Button {
                                            handleSwipeSave(entry: entry)
                                        } label: {
                                            Label("저장", systemImage: "checkmark")
                                        }
                                        .tint(.green)
                                    }
                                }
                            }
                        }
                    }
                    .contentMargins(.bottom, 24, for: .scrollContent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .animation(.smooth(duration: 0.3), value: pendingEntries.isEmpty && processingPending.isEmpty && failedPending.isEmpty)
            .animation(.smooth(duration: 0.25), value: processingPending.count)
            .animation(.smooth(duration: 0.25), value: failedPending.count)
            .navigationTitle("검토 (\(pendingEntries.count))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addSourceMenu
                }
            }
            .dropDestination(for: DroppedImage.self) { images, _ in
                Task { await ingestDroppedImages(images) }
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    dropOverlay
                }
            }
            .animation(.smooth(duration: 0.2), value: isDropTargeted)
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditorView(entry: entry)
        }
        .sheet(item: $manualEntry) { entry in
            EntryEditorView(entry: entry, insertOnSave: true)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoPickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            let snapshot = items
            photoPickerItems = []
            Task { await ingestPhotoPickerItems(snapshot) }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await ingestFileURLs(urls) }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            "가져오기 실패",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            ),
            presenting: importError
        ) { _ in
            Button("확인", role: .cancel) { importError = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "이 항목을 삭제할까요?",
            isPresented: Binding(
                get: { pendingToDelete != nil },
                set: { if !$0 { pendingToDelete = nil } }
            ),
            presenting: pendingToDelete
        ) { entry in
            Button("삭제", role: .destructive) {
                entry.status = .dismissed
                try? modelContext.save()
                pendingToDelete = nil
            }
            Button("취소", role: .cancel) {
                pendingToDelete = nil
            }
        } message: { _ in
            Text("검토 목록에서 사라져요.")
        }
        .alert(
            "저장하지 못했어요",
            isPresented: Binding(
                get: { swipeError != nil },
                set: { if !$0 { swipeError = nil } }
            ),
            presenting: swipeError
        ) { _ in
            Button("확인", role: .cancel) { swipeError = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isFMAvailable {
            ContentUnavailableView {
                Label("검토할 항목 없음", systemImage: "tray")
            } description: {
                Text("공유 시트로 보내거나 + 버튼으로 사진·파일·클립보드에서 추가하세요.")
            }
        } else {
            ContentUnavailableView {
                Label("자동 추출 사용 불가", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("Apple Intelligence가 꺼져 있거나 미지원 기기예요. 공유받은 사진·스크린샷은 자동으로 처리되지 않아요. + 버튼의 ‘수동 입력’으로 직접 추가하세요.")
            }
        }
    }

    private var fmUnavailableBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("자동 추출이 꺼져 있어요")
                    .font(.subheadline.weight(.semibold))
                Text("Apple Intelligence가 꺼져 있거나 미지원 기기라 사진에서 자동으로 추출되지 않아요. + 버튼의 ‘수동 입력’으로 직접 추가하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var addSourceMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("사진에서 선택", systemImage: "photo.on.rectangle")
            }
            Button {
                pasteFromClipboard()
            } label: {
                Label("클립보드에서 붙여넣기", systemImage: "doc.on.clipboard")
            }
            Button {
                isFileImporterPresented = true
            } label: {
                Label("파일에서 가져오기", systemImage: "folder")
            }
            Divider()
            Button {
                openManualEntry()
            } label: {
                Label("수동 입력", systemImage: "square.and.pencil")
            }
        } label: {
            Label("추가", systemImage: "plus")
        }
        .accessibilityLabel("항목 추가")
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
            }
            .overlay {
                Label("이미지 드롭", systemImage: "tray.and.arrow.down.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var processingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("\(processingPending.count)개 처리 중")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var failedPendingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("자동 처리되지 않은 이미지 \(failedPending.count)건")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Text("결제 정보를 찾지 못한 이미지예요. 영수증·결제 알림 스크린샷이 맞는지 확인해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("정리") {
                withAnimation(.smooth(duration: 0.25)) {
                    clearFailedPending()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func clearFailedPending() {
        for pending in failedPending {
            let url = AppGroup.inboxURL.appendingPathComponent(pending.filename)
            try? FileManager.default.removeItem(at: url)
            modelContext.delete(pending)
        }
        try? modelContext.save()
    }

    private func handleSwipeSave(entry: ParsedEntry) {
        if entry.merchant.isEmpty || entry.amount <= 0 {
            swipeError = "이 항목은 비어 있어요. 항목을 눌러 값을 채운 뒤 저장하세요."
            return
        }
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: modelContext)
        } catch {
            swipeError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func openManualEntry() {
        manualEntry = ParsedEntry(
            date: .now,
            amount: 0,
            merchant: "",
            confidence: 1.0
        )
    }
}

extension ReviewListView {
    fileprivate func pasteFromClipboard() {
        let board = UIPasteboard.general
        let images: [UIImage] = board.images ?? board.image.map { [$0] } ?? []
        guard !images.isEmpty else {
            importError = "클립보드에 이미지가 없어요."
            return
        }
        var inserted = 0
        for image in images {
            guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else { continue }
            do {
                try ImageImporter.ingest(data: data, suggestedExtension: "png", in: modelContext)
                inserted += 1
            } catch {
                importError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        if inserted > 0 {
            Task { await drain() }
        }
    }

    @MainActor
    fileprivate func ingestPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        var inserted = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension
                try ImageImporter.ingest(data: data, suggestedExtension: ext, in: modelContext)
                inserted += 1
            } catch {
                importError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        if inserted > 0 {
            await drain()
        }
    }

    @MainActor
    fileprivate func ingestFileURLs(_ urls: [URL]) async {
        var inserted = 0
        for url in urls where ingestOneFile(url) {
            inserted += 1
        }
        if inserted > 0 {
            await drain()
        }
    }

    fileprivate func ingestOneFile(_ url: URL) -> Bool {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension
            try ImageImporter.ingest(data: data, suggestedExtension: ext, in: modelContext)
            return true
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return false
        }
    }

    @MainActor
    fileprivate func ingestDroppedImages(_ images: [DroppedImage]) async {
        var inserted = 0
        for image in images {
            do {
                try ImageImporter.ingest(data: image.data, contentType: .image, in: modelContext)
                inserted += 1
            } catch {
                importError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        if inserted > 0 {
            await drain()
        }
    }

    @MainActor
    fileprivate func drain() async {
        await PendingProcessor.make(in: modelContext).drain(in: modelContext)
    }
}

private struct EntryRow: View {
    let entry: ParsedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.merchant)
                    .font(.body)
                Spacer()
                Text("\(entry.amount.formatted(.number))원")
                    .font(.body.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(entry.date, format: .dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let category = entry.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: .capsule)
                }
                if entry.confidence < 0.8 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("신뢰도 낮음")
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

#Preview {
    ReviewListView()
        .modelContainer(for: ParsedEntry.self, inMemory: true)
}
