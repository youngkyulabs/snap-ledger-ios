import Foundation
import SwiftData

@Model
final class AppSettings {
    var csvFolderBookmark: Data?
    var reminderEnabled: Bool = true
    var reminderHour: Int
    var reminderMinute: Int
    var categoryPresets: [String]
    var customExtractionGuide: String = ""
    var hasCompletedOnboarding: Bool = false

    init(
        csvFolderBookmark: Data? = nil,
        reminderEnabled: Bool = true,
        reminderHour: Int = 21,
        reminderMinute: Int = 0,
        categoryPresets: [String] = AppSettings.defaultPresets,
        customExtractionGuide: String = "",
        hasCompletedOnboarding: Bool = false
    ) {
        self.csvFolderBookmark = csvFolderBookmark
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.categoryPresets = categoryPresets
        self.customExtractionGuide = customExtractionGuide
        self.hasCompletedOnboarding = hasCompletedOnboarding
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
        "식비", "카페", "교통", "쇼핑", "공과금", "의료", "문화", "기타"
    ]
}
