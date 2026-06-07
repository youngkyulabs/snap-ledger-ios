import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct SyncCoordinatorReconciliationTests {
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
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncCoordinatorReconciliationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func configureFolder(_ dir: URL, in context: ModelContext) throws -> AppSettings {
        let settings = AppSettings(csvFolderBookmark: try BookmarkStore.makeBookmark(for: dir))
        context.insert(settings)
        try context.save()
        return settings
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    private func writeCSV(_ dir: URL, _ name: String, _ content: String) throws {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    @Test func monthStatusesIncludesReconciliationFiles() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)

        try writeCSV(
            dir, "reconciliations-2026-05.csv",
            "\u{FEFF}종류,날짜,계좌,항목,방향,금액,메모\n월급,,,월급,,3000000,\n"
        )

        let statuses = await SyncCoordinator().monthStatuses(in: context)
        let reconciliation = try #require(
            statuses.first { $0.kind == .reconciliation && $0.monthKey == "2026-05" }
        )
        #expect(reconciliation.state == .fileOnly)
        #expect(reconciliation.allowsImport)
        #expect(!reconciliation.allowsExport)
    }

    @Test func exportReconciliationMonthWritesFileAndUpdatesStatus() async throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        context.insert(
            MonthlyReconciliation(
                monthKey: 202_605,
                salaryAmount: 3_000_000,
                creditCardAmount: 450_000,
                savingsAmount: 500_000
            )
        )
        context.insert(
            AccountMonthlyBalance(
                monthKey: 202_605,
                accountName: "입출금",
                openingBalance: 1_000_000,
                closingBalance: 2_000_000
            )
        )
        try context.save()

        try sync.exportMonths(["2026-05"], kind: .reconciliation, in: context)

        let content = try String(
            contentsOf: dir.appendingPathComponent("reconciliations-2026-05.csv"),
            encoding: .utf8
        )
        #expect(content.contains("월급,,,월급,,3000000,"))
        #expect(content.contains("기초잔액,,입출금,,,1000000,"))

        let statuses = await sync.monthStatuses(in: context)
        let reconciliation = try #require(
            statuses.first { $0.kind == .reconciliation && $0.monthKey == "2026-05" }
        )
        #expect(reconciliation.state == .synced)
    }

    @Test func importReconciliationMonthReplacesExistingMonth() throws {
        let dir = makeTempDir()
        let context = try makeContext()
        try configureFolder(dir, in: context)
        let sync = SyncCoordinator()

        context.insert(MonthlyReconciliation(monthKey: 202_605, salaryAmount: 1))
        context.insert(AccountMonthlyBalance(monthKey: 202_605, accountName: "기존", openingBalance: 1))
        context.insert(
            CashAdjustment(
                monthKey: 202_605,
                date: makeDate(year: 2026, month: 5, day: 2),
                title: "기존",
                direction: .deposit,
                amount: 1
            )
        )
        try context.save()

        try writeCSV(
            dir, "reconciliations-2026-05.csv",
            """
            \u{FEFF}종류,날짜,계좌,항목,방향,금액,메모
            월급,,,월급,,3000000,
            카드사용액,,,카드 사용액,,450000,
            저축액,,,저축액,,500000,
            기초잔액,,입출금,,,1000000,
            기말잔액,,입출금,,,2000000,
            이자,,입출금,,,1200,
            자금변동,2026-05-15,,환급,입금,30000,교통비
            """
        )

        let summary = try sync.importMonths(["2026-05"], kind: .reconciliation, in: context)
        #expect(summary.totalRows == 7)
        #expect(summary.skippedRows == 0)

        let reconciliation = try #require(
            try context.fetch(FetchDescriptor<MonthlyReconciliation>()).first { $0.monthKey == 202_605 }
        )
        #expect(reconciliation.salaryAmount == 3_000_000)
        #expect(reconciliation.creditCardAmount == 450_000)
        #expect(reconciliation.savingsAmount == 500_000)

        let balances = try context.fetch(FetchDescriptor<AccountMonthlyBalance>())
        #expect(balances.count == 1)
        #expect(balances.first?.accountName == "입출금")
        #expect(balances.first?.openingBalance == 1_000_000)
        #expect(balances.first?.closingBalance == 2_000_000)
        #expect(balances.first?.interestAmount == 1_200)

        let adjustments = try context.fetch(FetchDescriptor<CashAdjustment>())
        #expect(adjustments.count == 1)
        #expect(adjustments.first?.title == "환급")
        #expect(adjustments.first?.direction == .deposit)
        #expect(adjustments.first?.amount == 30_000)
    }
}
