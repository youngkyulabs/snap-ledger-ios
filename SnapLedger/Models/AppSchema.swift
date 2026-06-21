import SwiftData

/// ModelContainer를 만드는 모든 곳(메인 앱, AppIntent)이 공유하는 단일 스키마 정의.
/// 새 @Model은 반드시 여기에만 등록한다.
///
/// 2-스토어 분리:
/// - `cloudModels`: CloudKit private DB로 동기화되는 "설정/의도" 데이터.
/// - `localModels`: App Group 로컬 스토어(인텐트와 공유, 기기-로컬) 데이터.
enum AppSchema {
    /// CloudKit 스토어로 동기화되는 모델. 비옵셔널 속성에 기본값·관계 없음·유니크 없음이어야 한다.
    static let cloudModels: [any PersistentModel.Type] = [
        CategoryBudget.self,
        CategoryPreset.self,
        SavedEntry.self,
    ]

    /// App Group 로컬 스토어 모델(인텐트와 공유).
    static let localModels: [any PersistentModel.Type] = [
        PendingImage.self,
        ParsedEntry.self,
        MerchantCategory.self,
        AppSettings.self,
        CSVFileState.self,
        MonthlyReconciliation.self,
        AccountMonthlyBalance.self,
        CashAdjustment.self,
        SavingsItem.self,
        CardUsageItem.self,
        IncomeItem.self,
    ]

    /// 전체 모델(컨테이너 생성용 합집합).
    static let models: [any PersistentModel.Type] = localModels + cloudModels
}
