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
            Tab("설정", systemImage: "gear") {
                SettingsView()
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pendingReviewCount)
        .sheet(isPresented: shouldShowOnboardingBinding) {
            if let settings = currentSettingsIfExists() {
                OnboardingView(settings: settings) {}
                    .interactiveDismissDisabled()
            }
        }
        .task {
            await drainPending()
            checkExternalChanges()
        }
        .alert(
            "파일이 외부에서 변경됐어요",
            isPresented: Binding(
                get: { !detectedChanges.isEmpty },
                set: { if !$0 { detectedChanges = [] } }
            )
        ) {
            Button("파일 → 앱 가져오기") { importDetectedChanges() }
            Button("나중에", role: .cancel) { detectedChanges = [] }
        } message: {
            Text(detectedChangesMessage)
        }
        .alert(
            "동기화",
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await drainPending()
                    checkExternalChanges()
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
    private func checkExternalChanges() {
        let sync = SyncCoordinator()
        sync.establishBaselineIfNeeded(in: modelContext)
        let changes = sync.detectChanges(in: modelContext)
        if !changes.isEmpty {
            detectedChanges = changes
        }
    }

    private var detectedChangesMessage: String {
        let months = detectedChanges.map(\.monthKey).joined(separator: ", ")
        return "\(months) 파일이 앱 밖에서 변경됐어요. 가져오면 해당 월 기록이 파일 내용으로 교체돼요. "
            + "(내 기록을 유지하려면 설정 → 파일 동기화의 ‘앱 → 파일 다시 쓰기’를 사용하세요.)"
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
