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

    /// (카테고리, 월) 레코드를 upsert. limit 0은 tombstone(이 달부터 한도 해제).
    @MainActor
    func setLimit(_ limit: Int, for category: String, effectiveFrom month: Int, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category && $0.effectiveFrom == month }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.monthlyLimit = limit
            existing.updatedAt = .now
        } else {
            context.insert(CategoryBudget(category: category, monthlyLimit: limit, effectiveFrom: month))
        }
        try context.save()
    }

    /// 이번 달부터 한도 해제(과거 보존). 현재 유효 한도가 있을 때만 tombstone을 남긴다.
    @MainActor
    func endBudget(for category: String, asOf month: Int, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        )
        let records = try context.fetch(descriptor)
        guard CategoryBudgetStore.resolveLimit(in: records, category: category, asOf: month) != nil else { return }
        try setLimit(0, for: category, effectiveFrom: month, in: context)
    }
}
