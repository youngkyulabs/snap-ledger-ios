import SwiftData

/// ModelContainer를 만드는 모든 곳(메인 앱, AppIntent)이 공유하는 단일 스키마 정의.
/// 같은 App Group 스토어를 서로 다른 스키마로 열면 마이그레이션 충돌이나
/// 누락 모델의 데이터 유실 위험이 있다 — 새 @Model은 반드시 여기에만 등록한다.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
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
        SavingsItem.self,
        CardUsageItem.self,
    ]
}
