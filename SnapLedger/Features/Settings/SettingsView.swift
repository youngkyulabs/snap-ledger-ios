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
                        AdvancedSettingsView()
                    } label: {
                        Label("고급 설정", systemImage: "slider.horizontal.3")
                    }
                }
                feedbackSection
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .navigationTitle("설정")
            .task { refreshSyncSummary() }
            .onChange(of: syncSignal) { _, _ in refreshSyncSummary() }
            .alert(
                "폴더 등록 실패",
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
                Text("알림을 받으려면 설정 → \(Self.appDisplayName) → 알림에서 켜주세요.")
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
            Button {
                showingPicker = true
            } label: {
                LabeledContent {
                    Text(currentFolderName() ?? "선택 안 됨")
                        .foregroundStyle(currentFolderName() == nil ? .secondary : .primary)
                } label: {
                    Label("저장 폴더", systemImage: "folder.fill")
                        .foregroundStyle(.primary)
                }
            }
            if settings.csvFolderBookmark != nil {
                syncStatusRow
            }
        } footer: {
            Text("월별 CSV 파일이 이 폴더에 저장돼요.")
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch syncSummary {
        case .empty:
            EmptyView()
        case .synced:
            LabeledContent {
                Label("동기화됨", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } label: {
                Label("폴더 상태", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.primary)
            }
        case .needsSync(let count):
            NavigationLink {
                FileSyncView()
            } label: {
                Label("폴더 상태", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.primary)
            }
            .badge(count)
        }
    }

    private var syncSignal: String {
        let latest = fileStates.map(\.lastSyncedAt).max()?.timeIntervalSince1970 ?? 0
        return "\(fileStates.count)-\(savedEntries.count)-\(latest)"
    }

    @MainActor
    private func refreshSyncSummary() {
        guard settings.csvFolderBookmark != nil else {
            syncSummary = .empty
            return
        }
        syncSummary = SyncCoordinator().folderSyncSummary(in: modelContext)
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
                    Label("설정 앱 열기", systemImage: "arrow.up.right.square")
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
            refreshSyncSummary()
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
