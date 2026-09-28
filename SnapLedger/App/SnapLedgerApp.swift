import SwiftUI
import SwiftData
import OSLog

@main
struct SnapLedgerApp: App {
    let modelContainer: ModelContainer

    init() {
        // Use in-memory container when running unit tests.
        if Self.isRunningUnitTests {
            modelContainer = Self.makeInMemoryContainer()
            return
        }

        // 1) Snapshot legacy unmigrated data.
        let legacy = Self.snapshotLegacyIfNeeded()

        // 2) Initialize two-store ModelContainer.
        let container = Self.makeContainer()

        // 3) Migrate legacy snapshot data into new stores.
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

    /// Returns whether unit tests are currently running.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Creates an in-memory ModelContainer for unit testing.
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(AppSchema.models), configurations: config)
        } catch {
            fatalError("Could not create in-memory test ModelContainer: \(error)")
        }
    }

    /// Creates a two-store ModelContainer with CloudKit sync, falling back to local storage.
    static func makeContainer() -> ModelContainer {
        // Local store stays unnamed so existing users' default.store is reused (naming it orphans their data).
        let local = ModelConfiguration(
            schema: Schema(AppSchema.localModels),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        // Cloud store must stay at this App Group location in both primary and fallback, or migrated data is stranded.
        let cloud = ModelConfiguration(
            "cloud",
            schema: Schema(AppSchema.cloudModels),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .private("iCloud.com.youngkyu.snapledger")
        )

        // Primary attempt: initialize container with CloudKit sync.
        if let container = try? ModelContainer(
            for: Schema(AppSchema.models),
            configurations: local, cloud
        ) {
            return container
        }

        // Fallback attempt: initialize container as local-only store.
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

    /// Legacy rows per migration group; nil skips that group this launch.
    struct LegacySnapshot {
        let budgets: [BudgetSnapshot]?
        let presets: [String]
        let entries: [EntrySnapshot]?
        let reconciliation: ReconciliationGroup?
        let merchants: [MerchantSnapshot]?
    }

    /// Reconciliation tables, read together because they migrate as one group.
    struct ReconciliationGroup {
        let reconciliations: [ReconciliationSnapshot]
        let accountBalances: [AccountBalanceSnapshot]
        let cashAdjustments: [CashAdjustmentSnapshot]
        let savings: [LineItemSnapshot]
        let cardUsage: [LineItemSnapshot]
        let income: [LineItemSnapshot]
    }

    /// Reads unmigrated legacy data into an in-memory snapshot.
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

        let settings: AppSettings?
        do {
            settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        } catch {
            logger.error("설정 읽기 실패 — 이번 실행에서는 마이그레이션을 건너뜁니다: \(String(describing: error))")
            return nil
        }
        let needBudgets = settings?.hasMigratedToCloudStore != true
        let needEntries = settings?.hasMigratedEntriesToCloudStore != true
        let needReconciliation = settings?.hasMigratedReconciliationToCloudStore != true
        let needMerchants = settings?.hasMigratedMerchantsToCloudStore != true
        guard needBudgets || needEntries || needReconciliation || needMerchants else { return nil }

        let presetsRaw = settings?.categoryPresets ?? AppSettings.defaultPresets
        // Groups are read separately so one unreadable table does not hold back the others.
        let snapshot = LegacySnapshot(
            budgets: readGroup("예산", when: needBudgets) { try CloudStoreMigration.snapshotBudgets(from: context) },
            presets: presetsRaw.isEmpty ? AppSettings.defaultPresets : presetsRaw,
            entries: readGroup("지출", when: needEntries) { try CloudStoreMigration.snapshotEntries(from: context) },
            reconciliation: readGroup("정산", when: needReconciliation) {
                try ReconciliationGroup(
                    reconciliations: CloudStoreMigration.snapshotReconciliations(from: context),
                    accountBalances: CloudStoreMigration.snapshotAccountBalances(from: context),
                    cashAdjustments: CloudStoreMigration.snapshotCashAdjustments(from: context),
                    savings: CloudStoreMigration.snapshotSavings(from: context),
                    cardUsage: CloudStoreMigration.snapshotCardUsage(from: context),
                    income: CloudStoreMigration.snapshotIncome(from: context)
                )
            },
            merchants: readGroup("가맹점 학습", when: needMerchants) { try CloudStoreMigration.snapshotMerchants(from: context) }
        )
        let hasWork = snapshot.budgets != nil || snapshot.entries != nil
            || snapshot.reconciliation != nil || snapshot.merchants != nil
        return hasWork ? snapshot : nil
    }

    /// Reads one group when it still needs migrating; a failed read skips it this launch so the next launch retries it.
    @MainActor
    private static func readGroup<T>(_ name: String, when needed: Bool, _ read: () throws -> T) -> T? {
        guard needed else { return nil }
        do {
            return try read()
        } catch {
            logger.error("\(name) 레거시 읽기 실패 — 다음 실행에서 다시 시도합니다: \(String(describing: error))")
            return nil
        }
    }

    /// Migrates snapshot data into new stores and sets completion flags.
    @MainActor
    static func runMigration(_ legacy: LegacySnapshot, in container: ModelContainer) {
        let context = ModelContext(container)
        let settings: AppSettings
        do {
            if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
                settings = existing
            } else {
                settings = AppSettings()
                context.insert(settings)
                // Commit the new row now so a group's rollback cannot discard it.
                try context.save()
            }
        } catch {
            logger.error("설정 준비 실패 — 마이그레이션을 다음 실행으로 미룹니다: \(String(describing: error))")
            return
        }
        // Each group commits its rows and its flag in one save; a failure rolls the group back so the next launch retries it.
        if let budgets = legacy.budgets {
            migrateGroup("예산", in: context) {
                try CloudStoreMigration.copyBudgets(budgets, into: context)
                try CloudStoreMigration.seedPresets(legacy.presets, into: context)
                settings.hasMigratedToCloudStore = true
            }
        }
        if let entries = legacy.entries {
            migrateGroup("지출", in: context) {
                try CloudStoreMigration.copyEntries(entries, into: context)
                settings.hasMigratedEntriesToCloudStore = true
            }
        }
        if let group = legacy.reconciliation {
            migrateGroup("정산", in: context) {
                try CloudStoreMigration.copyReconciliations(group.reconciliations, into: context)
                try CloudStoreMigration.copyAccountBalances(group.accountBalances, into: context)
                try CloudStoreMigration.copyCashAdjustments(group.cashAdjustments, into: context)
                try CloudStoreMigration.copySavings(group.savings, into: context)
                try CloudStoreMigration.copyCardUsage(group.cardUsage, into: context)
                try CloudStoreMigration.copyIncome(group.income, into: context)
                settings.hasMigratedReconciliationToCloudStore = true
            }
        }
        if let merchants = legacy.merchants {
            migrateGroup("가맹점 학습", in: context) {
                try CloudStoreMigration.copyMerchants(merchants, into: context)
                settings.hasMigratedMerchantsToCloudStore = true
            }
        }
    }

    @MainActor
    private static func migrateGroup(_ name: String, in context: ModelContext, _ body: () throws -> Void) {
        do {
            try body()
            try context.save()
        } catch {
            context.rollback()
            logger.error("\(name) 마이그레이션 실패: \(String(describing: error))")
        }
    }
}
