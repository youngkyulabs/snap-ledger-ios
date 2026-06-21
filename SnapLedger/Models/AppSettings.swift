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
    /// 기존 사용자의 예산·카테고리를 CloudKit 스토어로 1회성 이전했는지.
    /// 한 번 true가 되면, 사용자가 카테고리를 전부 지워도 재시드하지 않도록 이 플래그로만 가드한다.
    var hasMigratedToCloudStore: Bool = false
    /// 기존 사용자의 지출(SavedEntry)을 CloudKit 스토어로 1회성 이전했는지.
    /// Phase 1 플래그와 분리 — Phase 1 사용자는 hasMigratedToCloudStore가 이미 true라
    /// 재사용하면 지출 이전이 실행되지 않는다.
    var hasMigratedEntriesToCloudStore: Bool = false
    /// Phase 3: 정산 6종을 CloudKit 스토어로 이전 완료했는지. 독립 가드.
    var hasMigratedReconciliationToCloudStore: Bool = false
    /// Phase 3: MerchantCategory를 CloudKit 스토어로 이전 완료했는지. 독립 가드.
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
