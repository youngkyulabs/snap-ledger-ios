import SwiftData
import Testing
@testable import SnapLedger

struct AppSchemaTests {
    /// Verifies complete schema model registrations.
    @Test func includesEveryModelType() {
        let names = Set(Schema(AppSchema.models).entities.map(\.name))
        #expect(names == [
            "PendingImage", "ParsedEntry", "SavedEntry", "MerchantCategory", "AppSettings",
            "CategoryBudget", "MonthlyReconciliation", "AccountMonthlyBalance",
            "CashAdjustment", "SavingsItem", "CardUsageItem", "IncomeItem", "CategoryPreset",
        ])
    }

    /// Verifies CloudKit synced models.
    @Test func cloudAndLocalArePartition() {
        let cloud = Set(Schema(AppSchema.cloudModels).entities.map(\.name))
        let local = Set(Schema(AppSchema.localModels).entities.map(\.name))
        #expect(cloud == [
            "CategoryBudget", "CategoryPreset", "SavedEntry",
            "MonthlyReconciliation", "AccountMonthlyBalance", "CashAdjustment",
            "SavingsItem", "CardUsageItem", "IncomeItem", "MerchantCategory",
        ])
        #expect(cloud.isDisjoint(with: local))
        #expect(cloud.union(local) == Set(Schema(AppSchema.models).entities.map(\.name)))
    }
}
