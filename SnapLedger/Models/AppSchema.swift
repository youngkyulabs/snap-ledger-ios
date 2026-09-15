import SwiftData

/// SwiftData schema definitions. Register every new @Model here.
enum AppSchema {
    /// Models synchronized via CloudKit: every non-optional attribute needs a default, and no relationships or unique constraints are allowed.
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
