import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allParsedEntries: [ParsedEntry]
    @Query private var allSettings: [AppSettings]
    @State private var selectedTab: AppTab = .review
    @State private var settingsPath: [SettingsRoute] = []
    /// Identifier used to reset view to the current month on tab re-selection.
    @State private var statsResetNonce = 0
    @State private var budgetResetNonce = 0

    private var pendingReviewCount: Int {
        allParsedEntries.filter { $0.status == .pending }.count
    }

    /// Handles tab selection and updates the reset nonce on re-selection.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    switch newValue {
                    case .statistics: statsResetNonce += 1
                    case .budget: budgetResetNonce += 1
                    default: break
                    }
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("검토", systemImage: "tray.full", value: AppTab.review) {
                ReviewListView()
            }
            .badge(pendingReviewCount)
            Tab("최근 기록", systemImage: "list.bullet.rectangle", value: AppTab.history) {
                HistoryView()
            }
            Tab("통계", systemImage: "chart.pie", value: AppTab.statistics) {
                StatisticsView(resetNonce: statsResetNonce)
            }
            Tab("예산", systemImage: "wonsign.circle", value: AppTab.budget) {
                BudgetView(resetNonce: budgetResetNonce)
            }
            Tab("설정", systemImage: "gear", value: AppTab.settings) {
                SettingsView(path: $settingsPath)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pendingReviewCount)
        .sheet(isPresented: shouldShowOnboardingBinding) {
            if let settings = currentSettingsIfExists() {
                OnboardingView(settings: settings) {
                    // Drain pending images after onboarding completion.
                    Task { await drainPending() }
                }
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: pendingReviewCount, initial: true) { _, newCount in
            Task { await NotificationScheduler().syncIconBadge(count: newCount) }
        }
        // Handle app lifecycle state transitions.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                // Drain pending tasks only after onboarding is completed.
                guard hasCompletedOnboarding else { break }
                Task {
                    await drainPending()
                    // Refresh reminder notifications.
                    await refreshReminder()
                }
            case .background:
                BackgroundRefresh.schedule()
                Task { await refreshReminder() }
            default:
                break
            }
        }
        // Refresh cached category presets.
        .task { CategoryPresetStore().refreshCache(cloud: modelContext, local: modelContext) }
    }

    @MainActor
    private func drainPending() async {
        await PendingProcessor.make(in: modelContext).drain(in: modelContext)
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
        await ReminderRefresher.refresh(in: modelContext)
    }
}

/// Tab menu item identifier.
private enum AppTab: Hashable {
    case review, history, statistics, budget, settings
}

#Preview {
    ContentView()
}
