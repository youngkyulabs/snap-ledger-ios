import Foundation
import SwiftData

@Model
final class CategoryBudget {
    var category: String = ""
    /// > 0: 한도 / 0: 이 달부터 한도 해제(과거 보존용 tombstone)
    var monthlyLimit: Int = 0
    /// YYYYMM (예: 202606) — 이 달부터 적용, 다음 변경 전까지 매월 자동 반복
    var effectiveFrom: Int = 0
    var updatedAt: Date = Date.now

    init(category: String, monthlyLimit: Int, effectiveFrom: Int, updatedAt: Date = .now) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.effectiveFrom = effectiveFrom
        self.updatedAt = updatedAt
    }
}
