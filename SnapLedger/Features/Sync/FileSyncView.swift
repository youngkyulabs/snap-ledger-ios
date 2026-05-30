import SwiftData
import SwiftUI

/// 고급 설정 안의 파일 동기화 화면. 월별 상태를 보여주고 각 월 또는 전체를
/// 한 방향(파일→앱 / 앱→파일)으로 동기화한다.
struct FileSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var statuses: [MonthSyncStatus] = []
    @State private var prompt: SyncPrompt?
    @State private var resultMessage: String?

    private enum SyncPrompt: Identifiable {
        case month(MonthSyncStatus)
        case exportAll
        case importAll

        var id: String {
            switch self {
            case .month(let status): "month-\(status.monthKey)"
            case .exportAll: "export-all"
            case .importAll: "import-all"
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
        .navigationTitle("파일 동기화")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .confirmationDialog(
            "파일 동기화",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            titleVisibility: .visible,
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
    }

    private var listContent: some View {
        List {
            Section {
                Button {
                    prompt = .importAll
                } label: {
                    Label("파일 → 앱 전체 가져오기", systemImage: "arrow.down.doc")
                        .foregroundStyle(.primary)
                }
                Button {
                    prompt = .exportAll
                } label: {
                    Label("앱 → 파일 전체 다시 쓰기", systemImage: "arrow.up.doc")
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("월을 눌러 그 달만 따로 동기화할 수도 있어요.")
            }

            Section("월별") {
                if statuses.isEmpty {
                    Text("동기화할 월이 없어요.")
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
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    @ViewBuilder
    private func dialogActions(for prompt: SyncPrompt) -> some View {
        switch prompt {
        case .month(let status):
            if status.allowsImport {
                Button("파일 → 앱 가져오기", role: status.allowsExport ? nil : .destructive) {
                    runMonth(status.monthKey, importingFromFile: true)
                }
            }
            if status.allowsExport {
                Button("앱 → 파일 내보내기", role: status.allowsImport ? nil : .destructive) {
                    runMonth(status.monthKey, importingFromFile: false)
                }
            }
            Button("취소", role: .cancel) { self.prompt = nil }
        case .exportAll:
            Button("전체 파일 덮어쓰기", role: .destructive) { runBulk(importingFromFile: false) }
            Button("취소", role: .cancel) { self.prompt = nil }
        case .importAll:
            Button("전체 앱 기록 교체", role: .destructive) { runBulk(importingFromFile: true) }
            Button("취소", role: .cancel) { self.prompt = nil }
        }
    }

    private func dialogMessage(for prompt: SyncPrompt) -> String {
        switch prompt {
        case .month(let status):
            "\(monthLabel(status.monthKey)) — \(monthMessage(for: status.state))"
        case .exportAll:
            "앱의 모든 기록으로 폴더의 CSV를 다시 써요. 파일에만 있던 외부 변경은 사라져요."
        case .importAll:
            "폴더의 모든 CSV 내용으로 앱 기록을 교체해요. 앱에만 있던 변경은 사라져요."
        }
    }

    private func monthMessage(for state: MonthSyncStatus.State) -> String {
        switch state {
        case .synced: "앱과 파일이 같아요. 그래도 다시 동기화할 수 있어요."
        case .externalModified: "파일이 앱 밖에서 변경됐어요. 어느 쪽을 기준으로 맞출까요?"
        case .fileOnly: "이 달은 파일에만 있어요. 앱으로 가져올 수 있어요."
        case .appOnly: "이 달은 앱에만 있어요. 파일로 내보낼 수 있어요."
        case .notReady: "파일을 아직 받아오는 중이에요."
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
                resultMessage = "\(monthLabel(monthKey)) 파일을 앱 기록으로 다시 썼어요."
            }
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        reload()
    }

    private func runBulk(importingFromFile: Bool) {
        prompt = nil
        let sync = SyncCoordinator()
        do {
            if importingFromFile {
                let summary = try sync.importAll(in: modelContext)
                resultMessage = summary.userMessage
            } else {
                try sync.exportAll(in: modelContext)
                resultMessage = "앱 기록으로 모든 파일을 다시 썼어요."
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
        case .synced: "동기됨"
        case .externalModified: "외부 변경됨"
        case .fileOnly: "파일에만"
        case .appOnly: "앱에만"
        case .notReady: "받아오는 중"
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
