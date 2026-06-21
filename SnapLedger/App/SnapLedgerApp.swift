import SwiftUI
import SwiftData
import OSLog

@main
struct SnapLedgerApp: App {
    let modelContainer: ModelContainer

    init() {
        // 1) 줄어든 스키마로 App Group 스토어를 열기 전에, 구 예산·카테고리를 값으로 떠놓는다.
        //    (메인 컨테이너의 로컬 config는 CategoryBudget을 제외하므로 열면 그 테이블이 정리된다.)
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
        let cloud = ModelConfiguration(
            "cloud",
            schema: Schema(AppSchema.cloudModels),
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
    }

    /// 구 App Group 스토어를 전체 스키마로 열어 예산·카테고리를 값으로 읽는다.
    /// 이미 마이그레이션된 경우 nil(아무것도 하지 않음).
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
        if settings?.hasMigratedToCloudStore == true { return nil }

        let budgets = CloudStoreMigration.snapshotBudgets(from: context)
        let presets = settings?.categoryPresets ?? AppSettings.defaultPresets
        return LegacySnapshot(budgets: budgets, presets: presets.isEmpty ? AppSettings.defaultPresets : presets)
    }

    /// 스냅샷을 CloudKit 스토어로 이전하고 로컬 AppSettings 플래그를 세운다.
    @MainActor
    static func runMigration(_ legacy: LegacySnapshot, in container: ModelContainer) {
        let context = ModelContext(container)
        CloudStoreMigration.copyBudgets(legacy.budgets, into: context)
        CloudStoreMigration.seedPresets(legacy.presets, into: context)

        // 플래그는 로컬 AppSettings에 — 줄어든 로컬 스토어에서 읽고 쓴다.
        let settings: AppSettings
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = existing
        } else {
            settings = AppSettings()
            context.insert(settings)
        }
        settings.hasMigratedToCloudStore = true
        try? context.save()
    }
}
