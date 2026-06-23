import MessageUI
import SwiftData
import SwiftUI
import UIKit

/// 설정 화면에서 프로그래매틱하게 푸시할 수 있는 하위 화면.
enum SettingsRoute: Hashable {
    case fileSync
}

struct SettingsView: View {
    @Binding var path: [SettingsRoute]

    init(path: Binding<[SettingsRoute]> = .constant([])) {
        self._path = path
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var showingMailComposer = false
    @State private var feedbackFallbackShown = false
    @State private var notificationPermissionDeniedAlert = false
    #if DEBUG
    @State private var sampleDataAlert: String?
    #endif

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
        NavigationStack(path: $path) {
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
                #if DEBUG
                sampleDataSection
                #endif
                feedbackSection
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("정보", systemImage: "info.circle")
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .fileSync: FileSyncView()
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .navigationTitle("설정")
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
            #if DEBUG
            .alert("샘플 데이터", isPresented: Binding(
                get: { sampleDataAlert != nil },
                set: { if !$0 { sampleDataAlert = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(sampleDataAlert ?? "")
            }
            #endif
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
            if !hasFolder {
                Button {
                    showingPicker = true
                } label: {
                    Label("폴더 선택", systemImage: "folder.badge.plus")
                }
            } else {
                NavigationLink(value: SettingsRoute.fileSync) {
                    Label(currentFolderName() ?? "저장 폴더", systemImage: "folder.fill")
                }
            }
        } header: {
            Text("저장 폴더")
        } footer: {
            Text("앱 데이터는 iCloud로 자동 동기화돼요. 폴더는 월별 CSV 백업(내보내기)용이라 선택 사항이에요.")
        }
    }

    private var hasFolder: Bool {
        settings.csvFolderBookmark != nil
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
            folderError = nil
            // 새 폴더에 현재 앱 데이터를 백필한다(best-effort).
            try? SyncCoordinator().exportAll(in: modelContext)
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private var sampleDataSection: some View {
        Section {
            Button {
                Task { await seedSampleData() }
            } label: {
                Label("샘플 데이터 채우기", systemImage: "wand.and.stars")
            }
            Button(role: .destructive) {
                clearSampleData()
            } label: {
                Label("샘플 데이터 지우기", systemImage: "trash")
            }
        } header: {
            Text("개발자 · 스크린샷")
        } footer: {
            Text("디버그 전용. iCloud 로그아웃 상태에서만 채워집니다(오염 방지).")
        }
    }

    @MainActor
    private func seedSampleData() async {
        guard await SampleDataSeedGate.canSeedWithoutICloudPollution() else {
            sampleDataAlert = "iCloud에 로그인되어 있어 오염 방지를 위해 막았습니다. iCloud 로그아웃 후 다시 시도하세요."
            return
        }
        do {
            let counts = try SampleDataSeeder().seed(into: modelContext)
            sampleDataAlert = "채웠습니다 — 지출 \(counts.expenses)건, 정산 \(counts.reconciliationMonths)개월, 예산 \(counts.budgets)개."
        } catch {
            sampleDataAlert = "실패: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearSampleData() {
        do {
            try SampleDataSeeder().clear(in: modelContext)
            sampleDataAlert = "샘플 데이터를 지웠습니다."
        } catch {
            sampleDataAlert = "실패: \(error.localizedDescription)"
        }
    }
    #endif
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
