import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allParsedEntries: [ParsedEntry]
    @Query private var allSettings: [AppSettings]

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
        }
        .onChange(of: pendingReviewCount, initial: true) { _, newCount in
            Task { await NotificationScheduler().syncIconBadge(count: newCount) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await drainPending() }
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
