import SwiftData
import Testing
@testable import SnapLedger

struct AppSchemaTests {
    /// 메인 앱과 AppIntent가 같은 App Group 스토어를 여는데 스키마가 다르면
    /// 마이그레이션 충돌·데이터 유실 위험이 있다. 모든 @Model이 단일 정의에
    /// 등록되어 있는지 고정한다 — 새 모델을 추가하면 이 목록도 갱신할 것.
    @Test func includesEveryModelType() {
        let names = Set(Schema(AppSchema.models).entities.map(\.name))
        #expect(names == [
            "PendingImage", "ParsedEntry", "SavedEntry", "MerchantCategory", "AppSettings",
            "CSVFileState", "CategoryBudget", "MonthlyReconciliation", "AccountMonthlyBalance",
            "CashAdjustment", "SavingsItem", "CardUsageItem", "IncomeItem",
        ])
    }
}
