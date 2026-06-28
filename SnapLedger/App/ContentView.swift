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
    /// 이미 선택된 통계·예산 탭을 한 번 더 탭하면 그 탭을 현재 월로 되돌리기 위한 신호(카운터).
    @State private var statsResetNonce = 0
    @State private var budgetResetNonce = 0
    /// 저장 직후 잠깐 띄우는 예산 진행률 토스트. nil이면 표시 안 함.
    @State private var budgetToast: BudgetProgress.Line?
    /// 같은 카테고리를 연속 저장해도 토스트를 새로 띄우고 타이머를 리셋하기 위한 신호.
    @State private var toastNonce = 0

    private var pendingReviewCount: Int {
        allParsedEntries.filter { $0.status == .pending }.count
    }

    /// 토스트의 카테고리 색을 예산·통계 탭과 동일한 매핑으로 맞추기 위한 presets.
    private var budgetToastPresets: [String] {
        allSettings.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    /// 탭 선택 바인딩. 이미 선택된 탭을 다시 탭하면 같은 값으로 set이 호출되는데,
    /// 그때 통계·예산이면 리셋 신호를 올려 해당 화면을 현재 월로 되돌린다.
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
                ReviewListView { line in
                    budgetToast = line
                    toastNonce += 1
                }
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
        .overlay(alignment: .bottom) {
            if let budgetToast {
                BudgetToastView(line: budgetToast, presets: budgetToastPresets) { self.budgetToast = nil }
                    .id(toastNonce)
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: budgetToast)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pendingReviewCount)
        .sheet(isPresented: shouldShowOnboardingBinding) {
            if let settings = currentSettingsIfExists() {
                OnboardingView(settings: settings) {
                    // 온보딩 동안 미뤄둔 시작 작업을 완료 시점에 한 번 실행한다.
                    Task { await drainPending() }
                }
                .interactiveDismissDisabled()
            }
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
                    // 1회성 알림이 소비됐거나 검토를 끝낸 직후일 수 있으니
                    // 포그라운드 진입 시에도 최신 카운트로 재장전한다.
                    await refreshReminder()
                }
            case .background:
                BackgroundRefresh.schedule()
                Task { await refreshReminder() }
            default:
                break
            }
        }
        // 앱 진입(콜드 스타트·포그라운드 복귀) 시 원격 기기 변경을 로컬 캐시에 반영.
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

/// TabView 선택 식별자 (재선택 감지를 위해 값 기반 Tab으로 둔다).
private enum AppTab: Hashable {
    case review, history, statistics, budget, settings
}

#Preview {
    ContentView()
}
