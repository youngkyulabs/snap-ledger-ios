import SwiftData
import SwiftUI

/// Storage folder view providing export-all and folder change actions.
struct FileSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var resultMessage: String?
    @State private var isExporting = false
    @State private var folderReachable = true
    @State private var staleCount = 0
    @State private var confirmingPrune = false

    private var hasFolder: Bool {
        settingsList.first?.csvFolderBookmark != nil
    }

    var body: some View {
        Group {
            if !hasFolder {
                ContentUnavailableView {
                    Label("폴더 미설정", systemImage: "folder.badge.plus")
                } description: {
                    Text("저장 폴더를 먼저 선택해 주세요.")
                } actions: {
                    Button("폴더 선택") { showingPicker = true }
                }
            } else if !folderReachable {
                ContentUnavailableView {
                    Label("폴더를 찾을 수 없어요", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("폴더가 삭제·이동됐을 수 있어요. 파일 앱의 ‘최근 삭제된 항목’에 있다면 "
                        + "복원한 뒤 다시 열거나, 다른 폴더를 선택해 주세요.")
                } actions: {
                    Button("폴더 변경") { showingPicker = true }
                }
            } else {
                listContent
            }
        }
        .navigationTitle("저장 폴더")
        .navigationBarTitleDisplayMode(.inline)
        .task { folderReachable = SyncCoordinator().isFolderReachable(in: modelContext) ?? false }
        .sheet(isPresented: $showingPicker) {
            FolderPicker(onPick: handlePickedFolder)
                .ignoresSafeArea()
        }
        .alert(
            "내보내기",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            ),
            presenting: resultMessage
        ) { _ in
            Button("확인", role: .cancel) { resultMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "폴더 변경 실패",
            isPresented: Binding(
                get: { folderError != nil },
                set: { if !$0 { folderError = nil } }
            ),
            presenting: folderError
        ) { _ in
            Button("확인", role: .cancel) { folderError = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "기록이 없는 달의 파일 \(staleCount)개",
            isPresented: $confirmingPrune,
            titleVisibility: .visible
        ) {
            Button("내보내고 \(staleCount)개 삭제", role: .destructive) { exportAll(prune: true) }
            Button("내보내기만") { exportAll(prune: false) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 폴더에 앱에 기록이 없는 달의 CSV가 있어요. 새 기기라면 iCloud 동기화가 끝난 뒤에 삭제하세요.")
        }
    }

    private var listContent: some View {
        List {
            Section {
                Button {
                    startExportAll()
                } label: {
                    Label("전체 내보내기", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.primary)
                }
                .disabled(isExporting)
            } footer: {
                Text("앱에 있는 모든 지출·정산을 이 폴더의 월별 CSV로 다시 써요. "
                    + "앱에 기록이 없는 달의 파일이 있으면 지우기 전에 물어봐요.")
            }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("폴더 변경", systemImage: "folder.badge.gearshape")
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("다른 폴더를 고르면 현재 앱 데이터를 그 폴더로 다시 내보내요. 앱 기록은 그대로 남아요.")
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private func handlePickedFolder(_ url: URL) {
        guard let settings = settingsList.first else { return }
        do {
            try FolderBookmarkHelper.apply(url: url, to: settings, context: modelContext)
            folderError = nil
            folderReachable = true
            // Backfill existing data to newly selected folder.
            try? SyncCoordinator().exportAll(in: modelContext, pruneStale: false)
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }

    private func startExportAll() {
        // Ask before deleting; when nothing is stale or the listing fails, export without pruning.
        let stale = (try? SyncCoordinator().staleExports(in: modelContext)) ?? []
        if stale.isEmpty {
            exportAll(prune: false)
        } else {
            staleCount = stale.count
            confirmingPrune = true
        }
    }

    private func exportAll(prune: Bool) {
        isExporting = true
        // Yield to allow UI to update disabled state before running export.
        Task {
            defer { isExporting = false }
            await Task.yield()
            do {
                try SyncCoordinator().exportAll(in: modelContext, pruneStale: prune)
                resultMessage = prune
                    ? "앱의 모든 지출·정산을 폴더로 내보내고, 기록이 없는 달의 파일을 삭제했어요."
                    : "앱의 모든 지출·정산을 폴더로 내보냈어요."
            } catch {
                resultMessage = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
