import Foundation
import SwiftData

@Model
final class AppSettings {
    var csvFolderBookmark: Data?
    /// Whether reminder notifications are enabled.
    var reminderEnabled: Bool = false
    var reminderHour: Int
    var reminderMinute: Int
    var categoryPresets: [String]
    var customExtractionGuide: String = ""
    var hasCompletedOnboarding: Bool = false
    /// Whether budgets and category presets have migrated to CloudKit.
    var hasMigratedToCloudStore: Bool = false
    /// Whether saved entries have migrated to CloudKit.
    var hasMigratedEntriesToCloudStore: Bool = false
    /// Whether reconciliation records have migrated to CloudKit.
    var hasMigratedReconciliationToCloudStore: Bool = false
    /// Whether merchant category mappings have migrated to CloudKit.
    var hasMigratedMerchantsToCloudStore: Bool = false

    init(
        csvFolderBookmark: Data? = nil,
        reminderEnabled: Bool = false,
        reminderHour: Int = 21,
        reminderMinute: Int = 0,
        categoryPresets: [String] = AppSettings.defaultPresets,
        customExtractionGuide: String = "",
        hasCompletedOnboarding: Bool = false,
        hasMigratedToCloudStore: Bool = false,
        hasMigratedEntriesToCloudStore: Bool = false,
        hasMigratedReconciliationToCloudStore: Bool = false,
        hasMigratedMerchantsToCloudStore: Bool = false
    ) {
        self.csvFolderBookmark = csvFolderBookmark
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.categoryPresets = categoryPresets
        self.customExtractionGuide = customExtractionGuide
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasMigratedToCloudStore = hasMigratedToCloudStore
        self.hasMigratedEntriesToCloudStore = hasMigratedEntriesToCloudStore
        self.hasMigratedReconciliationToCloudStore = hasMigratedReconciliationToCloudStore
        self.hasMigratedMerchantsToCloudStore = hasMigratedMerchantsToCloudStore
    }

    @MainActor
    static func currentGuide(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<AppSettings>()
        return ((try? context.fetch(descriptor))?.first?.customExtractionGuide ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func currentCategories(in context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor))?.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    static let defaultPresets: [String] = [
        "식비", "카페", "생활", "교통", "쇼핑", "공과금", "구독", "의료", "문화", "기타"
    ]
}
