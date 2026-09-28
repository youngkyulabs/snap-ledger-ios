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

        do {
            let budgets = needBudgets ? try CloudStoreMigration.snapshotBudgets(from: context) : []
            let presetsRaw = settings?.categoryPresets ?? AppSettings.defaultPresets
            let presets = presetsRaw.isEmpty ? AppSettings.defaultPresets : presetsRaw
            let entries = needEntries ? try CloudStoreMigration.snapshotEntries(from: context) : []
            let reconciliations = needReconciliation ? try CloudStoreMigration.snapshotReconciliations(from: context) : []
            let accountBalances = needReconciliation ? try CloudStoreMigration.snapshotAccountBalances(from: context) : []
            let cashAdjustments = needReconciliation ? try CloudStoreMigration.snapshotCashAdjustments(from: context) : []
            let savings = needReconciliation ? try CloudStoreMigration.snapshotSavings(from: context) : []
            let cardUsage = needReconciliation ? try CloudStoreMigration.snapshotCardUsage(from: context) : []
            let income = needReconciliation ? try CloudStoreMigration.snapshotIncome(from: context) : []
            let merchants = needMerchants ? try CloudStoreMigration.snapshotMerchants(from: context) : []
            return LegacySnapshot(
                budgets: budgets, presets: presets, entries: entries,
                reconciliations: reconciliations, accountBalances: accountBalances,
                cashAdjustments: cashAdjustments, savings: savings, cardUsage: cardUsage,
                income: income, merchants: merchants,
                migrateBudgets: needBudgets, migrateEntries: needEntries,
                migrateReconciliation: needReconciliation, migrateMerchants: needMerchants
            )
        } catch {
            // Nothing is marked migrated, so the next launch retries.
            logger.error("레거시 스냅샷 읽기 실패 — 이번 실행에서는 마이그레이션을 건너뜁니다: \(String(describing: error))")
            return nil
        }
    }

    /// Migrates snapshot data into new stores and sets completion flags.
    @MainActor
    static func runMigration(_ legacy: LegacySnapshot, in container: ModelContainer) {
        let context = ModelContext(container)
        let settings: AppSettings
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = existing
        } else {
            settings = AppSettings()
            context.insert(settings)
        }
        // Each group is marked migrated only when its copy succeeded, so a failed group retries next launch.
        if legacy.migrateBudgets {
            do {
                try CloudStoreMigration.copyBudgets(legacy.budgets, into: context)
                try CloudStoreMigration.seedPresets(legacy.presets, into: context)
                settings.hasMigratedToCloudStore = true
            } catch {
                logger.error("예산 마이그레이션 실패: \(String(describing: error))")
            }
        }
        if legacy.migrateEntries {
            do {
                try CloudStoreMigration.copyEntries(legacy.entries, into: context)
                settings.hasMigratedEntriesToCloudStore = true
            } catch {
                logger.error("지출 마이그레이션 실패: \(String(describing: error))")
            }
        }
        if legacy.migrateReconciliation {
            do {
                try CloudStoreMigration.copyReconciliations(legacy.reconciliations, into: context)
                try CloudStoreMigration.copyAccountBalances(legacy.accountBalances, into: context)
                try CloudStoreMigration.copyCashAdjustments(legacy.cashAdjustments, into: context)
                try CloudStoreMigration.copySavings(legacy.savings, into: context)
                try CloudStoreMigration.copyCardUsage(legacy.cardUsage, into: context)
                try CloudStoreMigration.copyIncome(legacy.income, into: context)
                settings.hasMigratedReconciliationToCloudStore = true
            } catch {
                logger.error("정산 마이그레이션 실패: \(String(describing: error))")
            }
        }
        if legacy.migrateMerchants {
            do {
                try CloudStoreMigration.copyMerchants(legacy.merchants, into: context)
                settings.hasMigratedMerchantsToCloudStore = true
            } catch {
                logger.error("가맹점 학습 마이그레이션 실패: \(String(describing: error))")
            }
        }
        do {
            try context.save()
        } catch {
            logger.error("마이그레이션 완료 플래그 저장 실패: \(String(describing: error))")
        }
    }
}
