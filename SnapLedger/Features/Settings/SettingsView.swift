import MessageUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    // 동기화 배지를 앱 측 변경(저장·수정·삭제·수동 동기화)에 반응시키기 위한 신호원.
    @Query private var savedEntries: [SavedEntry]
    @Query private var fileStates: [CSVFileState]
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var showingMailComposer = false
    @State private var feedbackFallbackShown = false
    @State private var notificationPermissionDeniedAlert = false
    @State private var syncSummary: FolderSyncSummary = .empty

    private static let feedbackEmail = "youngkyulabs@gmail.com"

    private static let appDisplayName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SnapLedger"
    }()

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        NavigationStack {
            Form {
                csvFolderSection
                reminderSection
                fmAvailabilitySection
                Section {
                    NavigationLink {
                        CategoryEditorView()
                    } label: {
                        Label("카테고리", systemImage: "tag")
                    }
                }
                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Label("고급 설정", systemImage: "slider.horizontal.3")
                    }
                }
                feedbackSection
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("정보", systemImage: "info.circle")
                    }
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .navigationTitle("설정")
            .task { await refreshSyncSummary() }
            .onChange(of: syncSignal) { _, _ in Task { await refreshSyncSummary() } }
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
            .alert("메일 앱 열기 실패", isPresented: $feedbackFallbackShown) {
                Button("확인", role: .cancel) { }
            }
            .alert("알림 권한이 꺼져 있어요", isPresented: $notificationPermissionDeniedAlert) {
                Button("설정 열기") { openSystemSettingsURL() }
                Button("취소", role: .cancel) { }
            } message: {
                Text("알림을 받으려면 설정 → \(Self.appDisplayName) → 알림에서 켜 주세요.")
            }
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker(onPick: handlePickedFolder)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposeSheet(
                to: Self.feedbackEmail,
                subject: FeedbackMail.subject,
                body: feedbackBody
            ) {
                showingMailComposer = false
            }
            .ignoresSafeArea()
        }
    }

    private var csvFolderSection: some View {
        Section {
            // 폴더 설정 여부는 북마크 존재로 판단한다. 폴더가 삭제/이동돼 이름을
            // resolve하지 못해도 "폴더 미설정"으로 떨어지지 않게(=폴더 없음 경고 유지).
            if !hasFolder {
                Button {
                    showingPicker = true
                } label: {
                    Label("폴더 선택", systemImage: "folder.badge.plus")
                }
            } else if syncSummary == .folderMissing {
                // 폴더가 사라졌을 땐 폴더 상태 화면(어차피 "폴더 변경"뿐)을 거치지 않고
                // 행을 누르면 바로 피커를 연다.
                Button {
                    showingPicker = true
                } label: {
                    folderRowLabel.foregroundStyle(.primary)
                }
            } else {
                NavigationLink {
                    FileSyncView()
                } label: {
                    folderRowLabel
                }
            }
        } header: {
            Text("저장 폴더")
        } footer: {
            Text(folderFooterText)
        }
    }

    private var folderRowLabel: some View {
        LabeledContent {
            folderStatusIcon
        } label: {
            Label(currentFolderName() ?? "저장 폴더", systemImage: folderRowIcon)
        }
    }

    private var hasFolder: Bool {
        settings.csvFolderBookmark != nil
    }

    private var folderRowIcon: String {
        syncSummary == .folderMissing ? "folder.badge.questionmark" : "folder.fill"
    }

    private var folderFooterText: String {
        if hasFolder, syncSummary == .folderMissing {
            return "저장 폴더를 찾을 수 없어요. 폴더가 삭제·이동됐을 수 있어요. "
                + "파일 앱의 ‘최근 삭제된 항목’에 있다면 복원한 뒤 다시 열거나, 위 ‘저장 폴더’ 행을 눌러 다른 폴더를 선택해 주세요."
        }
        return "월별 CSV 파일이 이 폴더에 저장돼요."
    }

    @ViewBuilder
    private var folderStatusIcon: some View {
        switch syncSummary {
        case .empty:
            EmptyView()
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("동기화됨")
        case .needsSync:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("맞출 변경 사항 있음")
        case .folderMissing:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("폴더를 찾을 수 없음")
        }
    }

    private var syncSignal: String {
        let latest = fileStates.map(\.lastSyncedAt).max()?.timeIntervalSince1970 ?? 0
        return "\(fileStates.count)-\(savedEntries.count)-\(latest)"
    }

    @MainActor
    private func refreshSyncSummary() async {
        let newSummary: FolderSyncSummary
        if settings.csvFolderBookmark == nil {
            newSummary = .empty
        } else {
            newSummary = await SyncCoordinator().folderSyncSummary(in: modelContext)
        }
        // 상태 아이콘 등장/변경, 행 전환(링크↔피커 버튼)을 부드럽게.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            syncSummary = newSummary
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("검토 알림", isOn: reminderEnabledBinding)
            if settings.reminderEnabled {
                DatePicker(
                    "알림 시각",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } footer: {
            if settings.reminderEnabled {
                Text("매일 이 시각에 검토할 항목 알림을 보내요.")
            }
        }
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled },
            set: { newValue in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    settings.reminderEnabled = newValue
                }
                try? modelContext.save()
                if newValue {
                    Task { await ensureNotificationPermission() }
                }
            }
        )
    }

    @MainActor
    private func ensureNotificationPermission() async {
        let scheduler = NotificationScheduler()
        let status = await scheduler.authorizationStatus()
        switch OnboardingPermissionAction.decide(status: status) {
        case .requestAuthorization:
            let granted = await scheduler.requestPermissionIfNeeded()
            if !granted {
                rollbackReminder()
            }
        case .openSystemSettings:
            rollbackReminder()
        case .keepOn:
            break
        }
    }

    private func rollbackReminder() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.reminderEnabled = false
        }
        try? modelContext.save()
        notificationPermissionDeniedAlert = true
    }

    private func openSystemSettingsURL() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.reminderHour
                components.minute = settings.reminderMinute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderHour = components.hour ?? settings.reminderHour
                settings.reminderMinute = components.minute ?? settings.reminderMinute
                try? modelContext.save()
            }
        )
    }

    private var fmAvailabilitySection: some View {
        let status = AppleIntelligenceStatus.current
        return Section {
            HStack(spacing: 10) {
                Image(systemName: status.iconSystemName)
                    .foregroundStyle(color(for: status.severity))
                Text(status.shortLabel)
            }
            if status.offersSystemSettingsLink {
                Button {
                    openSystemSettingsURL()
                } label: {
                    Label("설정 열기", systemImage: "arrow.up.right.square")
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("자동 추출")
        } footer: {
            Text(status.detailMessage)
        }
    }

    private func color(for severity: AppleIntelligenceStatus.Severity) -> Color {
        switch severity {
        case .success: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var feedbackSection: some View {
        Section {
            Button {
                openFeedbackMail()
            } label: {
                Label("피드백 보내기", systemImage: "envelope.fill")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("의견·문의")
        } footer: {
            Text("기능 요청·버그·일반 의견 모두 환영해요.")
        }
    }

    private func openFeedbackMail() {
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            feedbackFallbackShown = true
        }
    }

    private var feedbackBody: String {
        FeedbackMail.body(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
    }

    private func currentFolderName() -> String? {
        guard let data = settings.csvFolderBookmark else { return nil }
        return (try? BookmarkStore.resolve(data).url.lastPathComponent)
    }

    private func handlePickedFolder(_ url: URL) {
        do {
            try FolderBookmarkHelper.apply(url: url, to: settings, context: modelContext)
            // 폴더가 바뀌면 이전 폴더 기준 지문이 무의미하므로 동기화 상태를 리셋한다.
            SyncCoordinator().resetSyncState(in: modelContext)
            folderError = nil
            Task { await refreshSyncSummary() }
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
