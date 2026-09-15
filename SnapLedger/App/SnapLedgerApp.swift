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

    /// Migrates snapshot data into new stores and sets completion flags.
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

        // Persist migration completion flag in local settings.
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
