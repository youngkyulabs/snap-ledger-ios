import SwiftData
import SwiftUI

/// 폴더 상태 화면 (설정 → 저장 폴더의 "폴더 상태"에서 진입). 월별 동기화
/// 상태를 보여주고 각 달을 한 방향(파일→앱 / 앱→파일)으로 맞춘다.
struct FileSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @State private var expenseStatuses: [MonthSyncStatus] = []
    @State private var reconciliationStatuses: [MonthSyncStatus] = []
    @State private var prompt: SyncPrompt?
    @State private var resultMessage: String?
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var folderReachable = true

    private enum SyncPrompt: Identifiable {
        case month(MonthSyncStatus)

        var id: String {
            switch self {
            case .month(let status): "month-\(status.id)"
            }
        }
    }

    private var hasFolder: Bool {
        settingsList.first?.csvFolderBookmark != nil
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { settingsList.first?.autoSyncEnabled ?? false },
            set: { newValue in
                settingsList.first?.autoSyncEnabled = newValue
                try? modelContext.save()
            }
        )
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
        .navigationTitle("폴더 상태")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showingPicker) {
            FolderPicker(onPick: handlePickedFolder)
                .ignoresSafeArea()
        }
        .alert(
            "파일 동기화",
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
                Toggle("앱 진입 시 자동으로 가져오기", isOn: autoSyncBinding)
            } footer: {
                Text("켜면 앱을 열 때 파일이 앱 밖에서 바뀐 달을 자동으로 파일 내용으로 맞춰요(파일 → 앱). "
                    + "끄면 바뀐 게 있을 때 알림으로 알려주고, 여기서 직접 맞출 수 있어요.")
            }
            if expenseStatuses.isEmpty && reconciliationStatuses.isEmpty {
                Section {
                    Text("맞출 달이 없어요.")
                        .foregroundStyle(.secondary)
                }
            } else {
                // 화면 전체 사용법 안내 — 특정 종류 섹션에 종속되지 않게 데이터 섹션 위에
                // 액션 없는 정보 항목으로 한 번 둔다. info 아이콘으로 탭 가능 행과 구분.
                Section {
                    Label {
                        Text(syncGuide)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                statusSection(title: "지출", statuses: expenseStatuses)
                statusSection(title: "정산", statuses: reconciliationStatuses)
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

    @ViewBuilder
    private func statusSection(title: String, statuses: [MonthSyncStatus]) -> some View {
        if !statuses.isEmpty {
            Section {
                ForEach(statuses) { status in
                    statusRow(for: status)
                }
            } header: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func statusRow(for status: MonthSyncStatus) -> some View {
        if status.needsResolution {
            Button {
                prompt = .month(status)
            } label: {
                MonthSyncRow(label: monthLabel(status.monthKey), state: status.state)
            }
            .buttonStyle(.plain)
        } else {
            // 최신·내려받는 중 — 맞출 게 없어 상태만 표시 (탭 액션 없음)
            MonthSyncRow(label: monthLabel(status.monthKey), state: status.state)
        }
    }

    private var syncGuide: String {
        "차이가 있는 달을 눌러 그 달의 지출·정산 CSV와 앱 내용을 맞춰요. "
            + "‘가져오기’는 파일 내용을 앱으로, ‘저장’은 앱 내용을 파일로 옮겨요."
    }

    private func handlePickedFolder(_ url: URL) {
        guard let settings = settingsList.first else { return }
        do {
            try FolderBookmarkHelper.apply(url: url, to: settings, context: modelContext)
            // 폴더가 바뀌면 이전 폴더 기준 지문이 무의미하므로 동기화 상태를 리셋한다.
            SyncCoordinator().resetSyncState(in: modelContext)
            folderError = nil
            Task { await reload() }
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
                    runMonth(status.monthKey, kind: status.kind, importingFromFile: true)
                }
            }
            if status.allowsExport {
                Button("앱 내용으로 저장", role: status.allowsImport ? nil : .destructive) {
                    runMonth(status.monthKey, kind: status.kind, importingFromFile: false)
                }
            }
            Button("취소", role: .cancel) { self.prompt = nil }
        }
    }

    private func dialogMessage(for prompt: SyncPrompt) -> String {
        switch prompt {
        case .month(let status):
            "\(monthLabel(status.monthKey)) \(status.kind.label) — \(monthMessage(for: status.state))"
        }
    }

    private func monthMessage(for state: MonthSyncStatus.State) -> String {
        switch state {
        case .synced: "앱과 파일 내용이 같아요."
        case .externalModified: "이 달 파일이 앱 밖에서 바뀌었어요. 어느 쪽 내용으로 맞출까요?"
        case .fileOnly: "이 달은 파일에만 있어요. 앱으로 가져올 수 있어요."
        case .appOnly: "이 달은 앱에만 있어요. 파일로 저장할 수 있어요."
        case .notReady: "iCloud에서 파일을 내려받는 중이에요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func reload() async {
        let sync = SyncCoordinator()
        let reachable = sync.isFolderReachable(in: modelContext) ?? false
        let newStatuses = await sync.monthStatuses(in: modelContext)
        // monthStatuses는 이미 종류·월(내림차순) 정렬 → 종류별로 갈라도 각 섹션 내 순서가 유지된다.
        // ForEach에서 inline filter하면 identity가 흔들리므로 미리 갈라 @State에 캐시한다.
        let expenses = newStatuses.filter { $0.kind == .expenses }
        let reconciliations = newStatuses.filter { $0.kind == .reconciliation }
        // 화면 전환(폴더 없음 ↔ 목록)과 월별 상태 변화(배지·탭가능 전환)를 부드럽게.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            folderReachable = reachable
            expenseStatuses = expenses
            reconciliationStatuses = reconciliations
        }
    }

    private func runMonth(_ monthKey: String, kind: SyncFileKind, importingFromFile: Bool) {
        prompt = nil
        let sync = SyncCoordinator()
        do {
            if importingFromFile {
                let summary = try sync.importMonths([monthKey], kind: kind, in: modelContext)
                resultMessage = summary.userMessage
            } else {
                try sync.exportMonths([monthKey], kind: kind, in: modelContext)
                resultMessage = "\(monthLabel(monthKey)) \(kind.label) 파일을 앱 내용으로 저장했어요."
            }
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        Task { await reload() }
    }

    private func monthLabel(_ key: String) -> String {
        CSVWriter.monthLabel(forMonthKey: key)
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
                .contentTransition(.opacity)
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
        case .synced: .green  // 설정 화면의 동기화됨(초록 체크)과 통일
        case .externalModified: .orange
        case .fileOnly, .appOnly: .blue
        case .notReady: .secondary
        }
    }
}
