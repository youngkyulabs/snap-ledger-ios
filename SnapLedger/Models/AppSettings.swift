import Foundation
import SwiftData

@Model
final class AppSettings {
    var csvFolderBookmark: Data?
    /// 알림은 명시적 opt-in. 사용자가 직접 켜고 권한을 허용해야만 true가 된다 (App Store 4.5.4).
    var reminderEnabled: Bool = false
    var reminderHour: Int
    var reminderMinute: Int
    var categoryPresets: [String]
    var customExtractionGuide: String = ""
    var hasCompletedOnboarding: Bool = false
    /// 파일 동기화 도입 전부터 폴더에 있던 CSV를 "외부 새 파일"로 오인하지 않도록,
    /// 첫 진입 시 현재 파일 지문을 baseline으로 한 번 기록했는지 여부.
    var hasSyncBaseline: Bool = false
    /// 앱 진입 시 외부에서 바뀐 CSV를 자동으로 파일→앱 가져올지. 기본 꺼짐(opt-in):
    /// 자동 적용은 앱 데이터를 파일 내용으로 조용히 덮어쓰므로 사용자가 직접 켠다.
    var autoSyncEnabled: Bool = false

    init(
        csvFolderBookmark: Data? = nil,
        reminderEnabled: Bool = false,
        reminderHour: Int = 21,
        reminderMinute: Int = 0,
        categoryPresets: [String] = AppSettings.defaultPresets,
        customExtractionGuide: String = "",
        hasCompletedOnboarding: Bool = false,
        hasSyncBaseline: Bool = false,
        autoSyncEnabled: Bool = false
    ) {
        self.csvFolderBookmark = csvFolderBookmark
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.categoryPresets = categoryPresets
        self.customExtractionGuide = customExtractionGuide
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasSyncBaseline = hasSyncBaseline
        self.autoSyncEnabled = autoSyncEnabled
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
