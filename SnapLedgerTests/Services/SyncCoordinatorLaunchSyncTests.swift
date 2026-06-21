import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorLaunchSyncTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            PendingImage.self,
            ParsedEntry.self,
            SavedEntry.self,
            MerchantCategory.self,
            AppSettings.self,
            CSVFileState.self,
            MonthlyReconciliation.self,
            AccountMonthlyBalance.self,
            CashAdjustment.self,
            SavingsItem.self,
            CardUsageItem.self,
            IncomeItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncCoordinatorLaunchSyncTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func configureFolder(_ dir: URL, in context: ModelContext) throws -> AppSettings {
        let settings = AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir))
        // baseline은 이전 세션에 잡힌 상태를 가정한다(진입 시 현재 파일을 흡수하지 않게).
        settings.hasSyncBaseline = true
        context.insert(settings)
        try context.save()
        return settings
    }

    private func writeCSV(_ dir: URL, _ name: String, _ content: String) throws {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    /// 정산 데이터를 앱에 넣고 파일로 export해 baseline(FileState)을 만든 뒤,
    /// 외부에서 파일을 새 내용으로 덮어쓴다. (수입 금액으로 변경 여부를 식별)
    private func seedReconciliationThenModifyFile(
        _ dir: URL, in context: ModelContext, sync: SyncCoordinator
    ) throws {
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000, sortOrder: 0))
        try context.save()
        try sync.exportMonths(["2026-05"], kind: .reconciliation, in: context)
        try writeCSV(
            dir, "reconciliations-2026-05.csv",
            "\u{FEFF}종류,항목,계좌,방향,금액,메모\n수입,월급,,,7777777,\n"
        )
    }

    @Test func detectChangesIncludesReconciliation() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        try seedReconciliationThenModifyFile(dir, in: context, sync: sync)

        let changes = await sync.detectChanges(in: context)
        let reconciliation = try #require(changes.first { $0.fileKind == .reconciliation })
        #expect(reconciliation.monthKey == "2026-05")
        #expect(reconciliation.kind == .modified)
    }

    @Test func autoApplyImportsReconciliationFromFile() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        try seedReconciliationThenModifyFile(dir, in: context, sync: sync)

        let outcome = await sync.resolveExternalChangesOnLaunch(autoApply: true, in: context)
        guard case .applied(let summary) = outcome else {
            Issue.record("autoApply가 .applied를 반환해야 함")
            return
        }
        #expect(summary.importedMonths.contains("2026-05"))
        // 파일 내용(7,777,777)이 앱에 반영돼야 한다.
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>()).filter { $0.monthKey == 202_605 }
        #expect(incomes.map(\.amount) == [7_777_777])
    }

    @Test func autoApplyKeepsAppDataOnMalformedFile() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000, sortOrder: 0))
        try context.save()
        try sync.exportMonths(["2026-05"], kind: .reconciliation, in: context)
        // 모든 행이 형식 불일치인(파싱 0행) 파일로 외부 변경.
        try writeCSV(
            dir, "reconciliations-2026-05.csv",
            "\u{FEFF}종류,항목,계좌,방향,금액,메모\n수입,월급,,,망가짐,\n카드사용액,카드,,,또깨짐,\n"
        )

        let outcome = await sync.resolveExternalChangesOnLaunch(autoApply: true, in: context)
        guard case .applied(let summary) = outcome else {
            Issue.record("autoApply가 .applied를 반환해야 함")
            return
        }
        #expect(summary.malformedMonths.contains("2026-05"))
        #expect(!summary.importedMonths.contains("2026-05"))
        // 앱 데이터는 보존된다.
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>()).filter { $0.monthKey == 202_605 }
        #expect(incomes.map(\.amount) == [3_000_000])
    }

    @Test func autoApplyOffReturnsDetectedWithoutImporting() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        try seedReconciliationThenModifyFile(dir, in: context, sync: sync)

        let outcome = await sync.resolveExternalChangesOnLaunch(autoApply: false, in: context)
        guard case .detected(let changes) = outcome else {
            Issue.record("autoApply=false는 .detected를 반환해야 함")
            return
        }
        #expect(!changes.isEmpty)
        // 자동 적용을 하지 않으므로 앱 데이터는 그대로(3,000,000).
        let incomes = try context.fetch(FetchDescriptor<IncomeItem>()).filter { $0.monthKey == 202_605 }
        #expect(incomes.map(\.amount) == [3_000_000])
    }

    @Test func noFalsePositiveAfterAppWrite() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()
        context.insert(MonthlyReconciliation(monthKey: 202_605))
        context.insert(IncomeItem(monthKey: 202_605, title: "월급", amount: 3_000_000, sortOrder: 0))
        try context.save()
        // 앱이 직접 파일을 쓴 직후(refreshFileState로 baseline 갱신됨).
        try sync.exportMonths(["2026-05"], kind: .reconciliation, in: context)

        let outcome = await sync.resolveExternalChangesOnLaunch(autoApply: true, in: context)
        guard case .applied(let summary) = outcome else {
            Issue.record("autoApply가 .applied를 반환해야 함")
            return
        }
        // 외부 변경이 없으므로 가져온 달이 없어야 한다(false positive 없음).
        #expect(summary.importedMonths.isEmpty)
    }
}
