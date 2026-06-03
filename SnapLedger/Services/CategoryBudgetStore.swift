import Foundation
import SwiftData

struct CategoryBudgetStore {
    /// YYYYMM 정수 키 (year*100 + month). StatisticsAggregation의 Int 월 키 관례와 동일.
    static func monthKey(from date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return (comps.year ?? 0) * 100 + (comps.month ?? 0)
    }

    /// (카테고리, 월)에 유효한 한도. effectiveFrom <= month 중 가장 최근 레코드의 monthlyLimit.
    /// 레코드가 없거나 tombstone(0)이면 nil(= 한도 없음).
    static func resolveLimit(in budgets: [CategoryBudget], category: String, asOf month: Int) -> Int? {
        let effective = budgets
            .filter { $0.category == category && $0.effectiveFrom <= month }
            .max { $0.effectiveFrom < $1.effectiveFrom }
        guard let limit = effective?.monthlyLimit, limit > 0 else { return nil }
        return limit
    }
}
