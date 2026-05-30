import MessageUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var showingMailComposer = false
    @State private var feedbackFallbackShown = false
    @State private var notificationPermissionDeniedAlert = false
    @State private var pendingSyncAction: SyncAction?
    @State private var syncResultMessage: String?

    private enum SyncAction: Identifiable {
        case export, importFile
        var id: Int { self == .export ? 0 : 1 }
    }

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
                syncSection
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
            .confirmationDialog(
                "파일 동기화",
                isPresented: Binding(
                    get: { pendingSyncAction != nil },
                    set: { if !$0 { pendingSyncAction = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSyncAction
            ) { action in
                Button(
                    action == .export ? "파일 덮어쓰기" : "앱 기록 교체",
                    role: .destructive
                ) {
                    runSync(action)
                }
                Button("취소", role: .cancel) { pendingSyncAction = nil }
            } message: { action in
                Text(action == .export
                    ? "앱의 모든 기록으로 폴더의 CSV를 다시 써요. 파일에만 있던 외부 변경은 사라져요."
                    : "폴더의 모든 CSV 내용으로 앱 기록을 교체해요. 앱에만 있던 변경은 사라져요.")
            }
            .alert(
                "파일 동기화",
                isPresented: Binding(
                    get: { syncResultMessage != nil },
                    set: { if !$0 { syncResultMessage = nil } }
                ),
                presenting: syncResultMessage
            ) { _ in
                Button("확인", role: .cancel) { syncResultMessage = nil }
            } message: { message in
                Text(message)
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
        } footer: {
            Text("월별 CSV 파일이 이 폴더에 저장돼요.")
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                pendingSyncAction = .export
            } label: {
                Label("앱 → 파일 다시 쓰기", systemImage: "arrow.up.doc")
                    .foregroundStyle(.primary)
            }
            Button {
                pendingSyncAction = .importFile
            } label: {
                Label("파일 → 앱 가져오기", systemImage: "arrow.down.doc")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("파일 동기화")
        } footer: {
            Text("앱과 폴더의 CSV를 수동으로 맞춰요. ‘다시 쓰기’는 앱 기록으로 파일을 덮어쓰고, "
                + "‘가져오기’는 파일 내용으로 앱 기록을 교체해요.")
        }
        .disabled(settings.csvFolderBookmark == nil)
    }

    @MainActor
    private func runSync(_ action: SyncAction) {
        pendingSyncAction = nil
        let sync = SyncCoordinator()
        do {
            switch action {
            case .export:
                try sync.exportAll(in: modelContext)
                syncResultMessage = "앱 기록으로 파일을 다시 썼어요."
            case .importFile:
                let summary = try sync.importAll(in: modelContext)
                syncResultMessage = summary.userMessage
            }
        } catch {
            syncResultMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
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
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
