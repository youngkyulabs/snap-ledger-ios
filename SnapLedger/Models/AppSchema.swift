import SwiftData

/// SwiftData schema definitions for the application.
enum AppSchema {
    /// Models synchronized via CloudKit.
    static let cloudModels: [any PersistentModel.Type] = [
        CategoryBudget.self,
        CategoryPreset.self,
        SavedEntry.self,
        MonthlyReconciliation.self,
        AccountMonthlyBalance.self,
        CashAdjustment.self,
        SavingsItem.self,
        CardUsageItem.self,
        IncomeItem.self,
        MerchantCategory.self,
    ]

    /// Local-only models stored in App Group container.
    static let localModels: [any PersistentModel.Type] = [
        PendingImage.self,
        ParsedEntry.self,
        AppSettings.self,
    ]

    /// All SwiftData models combined.
    static let models: [any PersistentModel.Type] = localModels + cloudModels
}
