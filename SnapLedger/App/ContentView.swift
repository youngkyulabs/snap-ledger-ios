import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allParsedEntries: [ParsedEntry]
    @Query private var allSettings: [AppSettings]
    @State private var detectedChanges: [DetectedChange] = []
    @State private var syncResultMessage: String?
    /// "나중에"로 미룬 달 — 이번 세션 동안 같은 달을 매 포그라운드마다 다시 묻지 않도록.
    @State private var snoozedMonths: Set<String> = []

    private var pendingReviewCount: Int {
        allParsedEntries.filter { $0.status == .pending }.count
    }

    var body: some View {
        TabView {
            Tab("검토", systemImage: "tray.full") {
                ReviewListView()
            }
            .badge(pendingReviewCount)
            Tab("최근 기록", systemImage: "list.bullet.rectangle") {
                HistoryView()
            }
            Tab("통계", systemImage: "chart.pie") {
                StatisticsView()
            }
            Tab("예산", systemImage: "wonsign.circle") {
                BudgetView()
            }
            Tab("설정", systemImage: "gear") {
                SettingsView()
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pendingReviewCount)
        .sheet(isPresented: shouldShowOnboardingBinding) {
            if let settings = currentSettingsIfExists() {
                OnboardingView(settings: settings) {
                    // 온보딩 동안 미뤄둔 시작 작업을 완료 시점에 한 번 실행한다.
                    Task {
                        await drainPending()
                        await checkExternalChanges()
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .alert(
            "파일이 앱 밖에서 바뀌었어요",
            isPresented: Binding(
                get: { !detectedChanges.isEmpty },
                set: { if !$0 { detectedChanges = [] } }
            )
        ) {
            Button("파일 내용 가져오기") { importDetectedChanges() }
            Button("나중에", role: .cancel) {
                snoozedMonths.formUnion(detectedChanges.map(\.monthKey))
                detectedChanges = []
            }
        } message: {
            Text(detectedChangesMessage)
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
        .onChange(of: pendingReviewCount, initial: true) { _, newCount in
            Task { await NotificationScheduler().syncIconBadge(count: newCount) }
        }
        // `initial: true`로 런치 시에도 정확히 한 번 실행된다 — 별도 `.task`와
        // scenePhase 핸들러가 같은 작업을 거의 동시에 두 번 돌리던 것을 단일화.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                // 온보딩이 끝나기 전에는 inbox 처리·변경 감지를 시작하지 않는다.
                // (완료 시점에 OnboardingView의 onComplete가 한 번 실행.)
                guard hasCompletedOnboarding else { break }
                Task {
                    await drainPending()
                    await checkExternalChanges()
                }
            case .background:
                BackgroundRefresh.schedule()
                Task { await refreshReminder() }
            default:
                break
            }
        }
    }

    @MainActor
    private func drainPending() async {
        await PendingProcessor.make(in: modelContext).drain(in: modelContext)
    }

    @MainActor
    private func checkExternalChanges() async {
        let sync = SyncCoordinator()
        sync.establishBaselineIfNeeded(in: modelContext)
        let changes = await sync.detectChanges(in: modelContext)
            .filter { !snoozedMonths.contains($0.monthKey) }
        if !changes.isEmpty {
            detectedChanges = changes
        }
    }

    private var detectedChangesMessage: String {
        let months = CSVWriter.monthLabels(detectedChanges.map(\.monthKey))
        return "\(months) 파일이 앱 밖에서 바뀌었어요. 가져오면 그 달 기록이 파일 내용으로 바뀌어요. "
            + "앱 내용을 그대로 두려면 ‘나중에’를 누르고, 설정 → 저장 폴더 → 폴더 상태에서 맞춰주세요."
    }

    @MainActor
    private func importDetectedChanges() {
        let keys = detectedChanges.map(\.monthKey)
        detectedChanges = []
        do {
            let summary = try SyncCoordinator().importMonths(keys, in: modelContext)
            syncResultMessage = summary.userMessage
        } catch {
            syncResultMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var hasCompletedOnboarding: Bool {
        allSettings.first?.hasCompletedOnboarding ?? false
    }

    private var shouldShowOnboardingBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = allSettings.first ?? ensureSettings()
                return !settings.hasCompletedOnboarding
            },
            set: { _ in }
        )
    }

    @MainActor
    private func ensureSettings() -> AppSettings {
        if let existing = allSettings.first { return existing }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    @MainActor
    private func currentSettingsIfExists() -> AppSettings? {
        allSettings.first ?? ensureSettings()
    }

    @MainActor
    private func refreshReminder() async {
        let scheduler = NotificationScheduler()
        let settings = currentSettings()
        guard settings.reminderEnabled else {
            scheduler.clear()
            return
        }
        let pendingCount = pendingParsedEntryCount()
        await scheduler.refresh(
            hour: settings.reminderHour,
            minute: settings.reminderMinute,
            pendingCount: pendingCount
        )
    }

    @MainActor
    private func pendingParsedEntryCount() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<ParsedEntry>())) ?? []
        return all.filter { $0.status == .pending }.count
    }

    @MainActor
    private func currentSettings() -> AppSettings {
        if let existing = try? modelContext.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }
}

#Preview {
    ContentView()
}
