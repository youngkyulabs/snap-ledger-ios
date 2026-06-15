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
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
}
