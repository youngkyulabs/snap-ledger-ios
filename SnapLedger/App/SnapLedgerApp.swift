import SwiftUI
import SwiftData

@main
struct SnapLedgerApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            PendingImage.self,
            ParsedEntry.self,
            SavedEntry.self,
            MerchantCategory.self,
            AppSettings.self,
            CSVFileState.self,
            CategoryBudget.self,
            MonthlyReconciliation.self,
            AccountMonthlyBalance.self,
            CashAdjustment.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        BackgroundRefresh.register(modelContainer: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
