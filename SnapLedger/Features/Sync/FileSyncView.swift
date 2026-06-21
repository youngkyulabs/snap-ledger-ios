import SwiftData
import SwiftUI

/// 저장 폴더 화면 (설정 → 저장 폴더에서 진입). CloudKit이 진실원이므로 폴더는
/// 월별 CSV 백업(한 방향 내보내기) 대상이다. 전체 내보내기와 폴더 변경만 제공한다.
struct FileSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var resultMessage: String?
    @State private var isExporting = false
    @State private var folderReachable = true

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
    }

    private var listContent: some View {
        List {
            Section {
                Button {
                    exportAll()
                } label: {
                    Label("전체 내보내기", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.primary)
                }
                .disabled(isExporting)
            } footer: {
                Text("앱에 있는 모든 지출·정산을 이 폴더의 월별 CSV로 다시 써요. "
                    + "평소 저장할 때도 자동으로 내보내지므로 보통은 필요 없어요.")
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
            // 새 폴더에 현재 앱 데이터를 백필한다(best-effort).
            try? SyncCoordinator().exportAll(in: modelContext)
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }

    private func exportAll() {
        isExporting = true
        defer { isExporting = false }
        do {
            try SyncCoordinator().exportAll(in: modelContext)
            resultMessage = "앱의 모든 지출·정산을 폴더로 내보냈어요."
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
