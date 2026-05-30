import SwiftData
import SwiftUI

/// 폴더 상태 화면 (설정 → 저장 폴더의 "폴더 상태"에서 진입). 월별 동기화
/// 상태를 보여주고 각 달을 한 방향(파일→앱 / 앱→파일)으로 맞춘다.
struct FileSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var statuses: [MonthSyncStatus] = []
    @State private var prompt: SyncPrompt?
    @State private var resultMessage: String?
    @State private var showingPicker = false
    @State private var folderError: String?

    private enum SyncPrompt: Identifiable {
        case month(MonthSyncStatus)

        var id: String {
            switch self {
            case .month(let status): "month-\(status.monthKey)"
            }
        }
    }

    private var hasFolder: Bool {
        settingsList.first?.csvFolderBookmark != nil
    }

    var body: some View {
        Group {
            if hasFolder {
                listContent
            } else {
                ContentUnavailableView(
                    "폴더 미설정",
                    systemImage: "folder.badge.questionmark",
                    description: Text("설정에서 저장 폴더를 먼저 골라주세요.")
                )
            }
        }
        .navigationTitle("폴더 상태")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .sheet(isPresented: $showingPicker) {
            FolderPicker(onPick: handlePickedFolder)
                .ignoresSafeArea()
        }
        .alert(
            "동기화",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { prompt in
            dialogActions(for: prompt)
        } message: { prompt in
            Text(dialogMessage(for: prompt))
        }
        .alert(
            "파일 동기화",
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
                if statuses.isEmpty {
                    Text("맞출 달이 없어요.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(statuses) { status in
                        Button {
                            prompt = .month(status)
                        } label: {
                            MonthSyncRow(label: monthLabel(status.monthKey), state: status.state)
                        }
                        .buttonStyle(.plain)
                        .disabled(status.state == .notReady)
                    }
                }
            } header: {
                Text("월별")
            } footer: {
                Text("달을 눌러 그 달의 앱 기록과 파일 내용을 맞춰요. "
                    + "‘가져오기’는 파일 내용을 앱으로, ‘저장’은 앱 내용을 파일로 옮겨요.")
            }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("폴더 변경", systemImage: "folder.badge.gearshape")
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("다른 폴더를 고르면 그 폴더의 CSV를 기준으로 다시 맞춰요. 현재 앱 기록은 그대로 남아요.")
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private func handlePickedFolder(_ url: URL) {
        guard let settings = settingsList.first else { return }
        do {
            try FolderBookmarkHelper.apply(url: url, to: settings, context: modelContext)
            // 폴더가 바뀌면 이전 폴더 기준 지문이 무의미하므로 동기화 상태를 리셋한다.
            SyncCoordinator().resetSyncState(in: modelContext)
            folderError = nil
            reload()
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func dialogActions(for prompt: SyncPrompt) -> some View {
        switch prompt {
        case .month(let status):
            if status.allowsImport {
                Button("파일 내용 가져오기", role: status.allowsExport ? nil : .destructive) {
                    runMonth(status.monthKey, importingFromFile: true)
                }
            }
            if status.allowsExport {
                Button("앱 내용으로 저장", role: status.allowsImport ? nil : .destructive) {
                    runMonth(status.monthKey, importingFromFile: false)
                }
            }
            Button("취소", role: .cancel) { self.prompt = nil }
        }
    }

    private func dialogMessage(for prompt: SyncPrompt) -> String {
        switch prompt {
        case .month(let status):
            "\(monthLabel(status.monthKey)) — \(monthMessage(for: status.state))"
        }
    }

    private func monthMessage(for state: MonthSyncStatus.State) -> String {
        switch state {
        case .synced: "앱과 파일 내용이 같아요. 그래도 다시 맞출 수 있어요."
        case .externalModified: "이 달 파일이 앱 밖에서 바뀌었어요. 어느 쪽 내용으로 맞출까요?"
        case .fileOnly: "이 달은 파일에만 있어요. 앱으로 가져올 수 있어요."
        case .appOnly: "이 달은 앱에만 있어요. 파일로 저장할 수 있어요."
        case .notReady: "iCloud에서 파일을 내려받는 중이에요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func reload() {
        statuses = SyncCoordinator().monthStatuses(in: modelContext)
    }

    private func runMonth(_ monthKey: String, importingFromFile: Bool) {
        prompt = nil
        let sync = SyncCoordinator()
        do {
            if importingFromFile {
                let summary = try sync.importMonths([monthKey], in: modelContext)
                resultMessage = summary.userMessage
            } else {
                try sync.exportMonths([monthKey], in: modelContext)
                resultMessage = "\(monthLabel(monthKey)) 파일을 앱 내용으로 저장했어요."
            }
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        reload()
    }

    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return key
        }
        return "\(year)년 \(month)월"
    }
}

private struct MonthSyncRow: View {
    let label: String
    let state: MonthSyncStatus.State

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(badgeText)
                .font(.caption.weight(.medium))
                .foregroundStyle(badgeColor)
        }
        .contentShape(.rect)
    }

    private var badgeText: String {
        switch state {
        case .synced: "최신"
        case .externalModified: "파일 변경됨"
        case .fileOnly: "파일에만 있음"
        case .appOnly: "앱에만 있음"
        case .notReady: "내려받는 중"
        }
    }

    private var badgeColor: Color {
        switch state {
        case .synced: .secondary
        case .externalModified: .orange
        case .fileOnly, .appOnly: .blue
        case .notReady: .secondary
        }
    }
}
