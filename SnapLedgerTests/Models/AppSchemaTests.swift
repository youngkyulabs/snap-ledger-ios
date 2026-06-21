import SwiftData
import Testing
@testable import SnapLedger

struct AppSchemaTests {
    /// 메인 앱과 AppIntent가 같은 App Group 스토어를 여는데 스키마가 다르면
    /// 마이그레이션 충돌·데이터 유실 위험이 있다. 전체 모델 목록을 고정한다.
    @Test func includesEveryModelType() {
        let names = Set(Schema(AppSchema.models).entities.map(\.name))
        #expect(names == [
            "PendingImage", "ParsedEntry", "SavedEntry", "MerchantCategory", "AppSettings",
            "CSVFileState", "CategoryBudget", "MonthlyReconciliation", "AccountMonthlyBalance",
            "CashAdjustment", "SavingsItem", "CardUsageItem", "IncomeItem", "CategoryPreset",
        ])
    }

    /// CloudKit 스토어로 가는 모델은 예산·프리셋뿐. 나머지는 전부 로컬.
    @Test func cloudAndLocalArePartition() {
        let cloud = Set(Schema(AppSchema.cloudModels).entities.map(\.name))
        let local = Set(Schema(AppSchema.localModels).entities.map(\.name))
        #expect(cloud == ["CategoryBudget", "CategoryPreset"])
        #expect(cloud.isDisjoint(with: local))
        #expect(cloud.union(local) == Set(Schema(AppSchema.models).entities.map(\.name)))
    }
}
