import SwiftUI
import SwiftData
import OSLog
import UserNotifications

@main
struct SnapLedgerApp: App {
    let modelContainer: ModelContainer
    /// foreground 예산 알림을 배너로 띄우는 델리게이트. UNUserNotificationCenter가 weak로
    /// 잡으므로 앱 수명 동안 살아있도록 여기서 보유한다.
    private let notificationPresenter = NotificationPresenter()

    init() {
        // 유닛테스트 호스트에서는 프로덕션 런치 경로(앱그룹 스토어 열기·CloudKit·마이그레이션·
        // 백그라운드 등록)를 건너뛰고 순수 in-memory 컨테이너로 뜬다. 유닛테스트는 각자
        // 자신의 컨테이너를 만들므로 호스트 컨테이너에 의존하지 않는다. (UI 테스트는 별도
        // 프로세스로 앱을 정상 실행하므로 이 분기에 걸리지 않는다.)
        if Self.isRunningUnitTests {
            modelContainer = Self.makeInMemoryContainer()
            return
        }

        // foreground에서 예산 임계 알림을 배너로 띄우기 위해 델리게이트를 등록한다.
        UNUserNotificationCenter.current().delegate = notificationPresenter

        // 1) 줄어든 스키마로 App Group 스토어를 열기 전에, 아직 이전 안 된 예산·카테고리·지출을
        //    값으로 떠놓는다. (메인 컨테이너의 로컬 config는 이 모델들을 제외하므로 열면 정리된다.)
        let legacy = Self.snapshotLegacyIfNeeded()

        // 2) 2-스토어 컨테이너 생성 (iCloud 미로그인 시 로컬 전용 폴백).
        let container = Self.makeContainer()

        // 3) 스냅샷이 있으면 CloudKit 스토어로 이전하고 플래그를 세운다(멱등).
        if let legacy {
            Self.runMigration(legacy, in: container)
        }

        modelContainer = container
        BackgroundRefresh.register(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

private extension SnapLedgerApp {
    static let logger = Logger(subsystem: "com.youngkyu.snapledger", category: "app")

    /// 유닛테스트 호스트 여부. xcodebuild test가 XCTest 프레임워크를 로드하므로 호스트 앱
    /// 프로세스에서 XCTestCase 심볼이 존재한다. UI 테스트 대상 앱 프로세스에는 없다.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// 테스트용 순수 in-memory 컨테이너(전체 스키마, CloudKit 미사용).
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(AppSchema.models), configurations: config)
        } catch {
            fatalError("Could not create in-memory test ModelContainer: \(error)")
        }
    }

    /// 2-스토어 ModelContainer를 생성한다.
    /// 1차 시도: CloudKit 동기화 포함 (iCloud 로그인 환경).
    /// 2차 시도: cloud config도 로컬 전용으로 폴백 (iCloud 미로그인·테스트 클론 크래시 방지).
    ///   설계 원칙 "iCloud 미로그인 → 로컬 전용 스토어, 동기화만 안 됨(크래시 없음)"을 구현한다.
    static func makeContainer() -> ModelContainer {
        // 로컬 스토어는 이름을 주지 않아 기존 사용자의 default.store를 그대로 연다.
        // (이름을 주면 새 빈 파일이 생겨 업데이트 시 기존 데이터가 고아가 된다.)
        let local = ModelConfiguration(
            schema: Schema(AppSchema.localModels),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        // cloud 스토어는 primary·fallback 모두 같은 App Group 위치의 cloud.store를 연다.
        // (위치가 갈리면, fallback으로 이전한 데이터를 다음 실행의 primary가 못 읽어 고립된다.)
        let cloud = ModelConfiguration(
            "cloud",
            schema: Schema(AppSchema.cloudModels),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .private("iCloud.com.youngkyu.snapledger")
        )

        // 1차 시도: CloudKit 동기화 포함 컨테이너.
        if let container = try? ModelContainer(
            for: Schema(AppSchema.models),
            configurations: local, cloud
        ) {
            return container
        }

        // 2차 시도: iCloud 미로그인 또는 시뮬레이터 등 CloudKit 초기화 실패 시 로컬 전용으로 폴백.
        logger.warning("CloudKit 컨테이너 초기화 실패 — 로컬 전용 폴백으로 재시도합니다.")
        let cloudFallback = ModelConfiguration(
            "cloud",
            schema: Schema(AppSchema.cloudModels),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: local, cloudFallback
            )
            logger.info("로컬 전용 폴백 컨테이너로 실행 중 (동기화 비활성).")
            return container
        } catch let fallbackError {
            fatalError("Could not create ModelContainer (fallback also failed): \(fallbackError)")
        }
    }

    struct LegacySnapshot {
        let budgets: [BudgetSnapshot]
        let presets: [String]
        let entries: [EntrySnapshot]
        let reconciliations: [ReconciliationSnapshot]
        let accountBalances: [AccountBalanceSnapshot]
        let cashAdjustments: [CashAdjustmentSnapshot]
        let savings: [LineItemSnapshot]
        let cardUsage: [LineItemSnapshot]
        let income: [LineItemSnapshot]
        let merchants: [MerchantSnapshot]
        let migrateBudgets: Bool
        let migrateEntries: Bool
        let migrateReconciliation: Bool
        let migrateMerchants: Bool
    }

    /// 구 App Group 스토어를 전체 스키마로 한 번 열어, 아직 이전 안 된 데이터를 값으로 읽는다.
    /// 예산·지출·정산·머천트 모두 이전 완료면 nil(아무것도 하지 않음).
    @MainActor
    static func snapshotLegacyIfNeeded() -> LegacySnapshot? {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: config) else { return nil }
        let context = ModelContext(container)

        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        let needBudgets = settings?.hasMigratedToCloudStore != true
        let needEntries = settings?.hasMigratedEntriesToCloudStore != true
        let needReconciliation = settings?.hasMigratedReconciliationToCloudStore != true
        let needMerchants = settings?.hasMigratedMerchantsToCloudStore != true
        guard needBudgets || needEntries || needReconciliation || needMerchants else { return nil }

        let budgets = needBudgets ? CloudStoreMigration.snapshotBudgets(from: context) : []
        let presetsRaw = settings?.categoryPresets ?? AppSettings.defaultPresets
        let presets = presetsRaw.isEmpty ? AppSettings.defaultPresets : presetsRaw
        let entries = needEntries ? CloudStoreMigration.snapshotEntries(from: context) : []

        let reconciliations = needReconciliation ? CloudStoreMigration.snapshotReconciliations(from: context) : []
        let accountBalances = needReconciliation ? CloudStoreMigration.snapshotAccountBalances(from: context) : []
        let cashAdjustments = needReconciliation ? CloudStoreMigration.snapshotCashAdjustments(from: context) : []
        let savings = needReconciliation ? CloudStoreMigration.snapshotSavings(from: context) : []
        let cardUsage = needReconciliation ? CloudStoreMigration.snapshotCardUsage(from: context) : []
        let income = needReconciliation ? CloudStoreMigration.snapshotIncome(from: context) : []
        let merchants = needMerchants ? CloudStoreMigration.snapshotMerchants(from: context) : []

        return LegacySnapshot(
            budgets: budgets, presets: presets, entries: entries,
            reconciliations: reconciliations, accountBalances: accountBalances,
            cashAdjustments: cashAdjustments, savings: savings, cardUsage: cardUsage,
            income: income, merchants: merchants,
            migrateBudgets: needBudgets, migrateEntries: needEntries,
            migrateReconciliation: needReconciliation, migrateMerchants: needMerchants
        )
    }

    /// 스냅샷을 CloudKit 스토어로 이전하고 로컬 AppSettings 플래그를 세운다.
    @MainActor
    static func runMigration(_ legacy: LegacySnapshot, in container: ModelContainer) {
        let context = ModelContext(container)
        if legacy.migrateBudgets {
            CloudStoreMigration.copyBudgets(legacy.budgets, into: context)
            CloudStoreMigration.seedPresets(legacy.presets, into: context)
        }
        if legacy.migrateEntries {
            CloudStoreMigration.copyEntries(legacy.entries, into: context)
        }
        if legacy.migrateReconciliation {
            CloudStoreMigration.copyReconciliations(legacy.reconciliations, into: context)
            CloudStoreMigration.copyAccountBalances(legacy.accountBalances, into: context)
            CloudStoreMigration.copyCashAdjustments(legacy.cashAdjustments, into: context)
            CloudStoreMigration.copySavings(legacy.savings, into: context)
            CloudStoreMigration.copyCardUsage(legacy.cardUsage, into: context)
            CloudStoreMigration.copyIncome(legacy.income, into: context)
        }
        if legacy.migrateMerchants {
            CloudStoreMigration.copyMerchants(legacy.merchants, into: context)
        }

        // 플래그는 로컬 AppSettings에 — 줄어든 로컬 스토어에서 읽고 쓴다.
        let settings: AppSettings
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = existing
        } else {
            settings = AppSettings()
            context.insert(settings)
        }
        if legacy.migrateBudgets { settings.hasMigratedToCloudStore = true }
        if legacy.migrateEntries { settings.hasMigratedEntriesToCloudStore = true }
        if legacy.migrateReconciliation { settings.hasMigratedReconciliationToCloudStore = true }
        if legacy.migrateMerchants { settings.hasMigratedMerchantsToCloudStore = true }
        try? context.save()
    }
}
