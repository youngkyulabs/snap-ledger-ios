import Foundation
import SwiftData

struct CategoryBudgetStore {
    /// YYYYMM 정수 키 (year*100 + month). StatisticsAggregation의 Int 월 키 관례와 동일.
    static func monthKey(from date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return (comps.year ?? 0) * 100 + (comps.month ?? 0)
    }

    /// YYYYMM 키의 다음 달 키 (12월 → 다음 해 1월).
    static func nextMonthKey(_ key: Int) -> Int {
        let year = key / 100
        let month = key % 100
        return month >= 12 ? (year + 1) * 100 + 1 : key + 1
    }

    /// YYYYMM 키의 이전 달 키 (1월 → 전 해 12월).
    static func previousMonthKey(_ key: Int) -> Int {
        let year = key / 100
        let month = key % 100
        return month <= 1 ? (year - 1) * 100 + 12 : key - 1
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

    /// 과거 달 단일 편집: month에만 새 한도를 적용하고 그 이후 달(특히 이번 달)에는 영향을 주지 않는다.
    /// effectiveFrom 모델은 한 레코드를 다음 변경 전까지 매월 전파하므로, month 레코드를 upsert한 뒤
    /// 다음 달(month+1)에 명시 레코드가 없고 전파가 실제로 바뀌는 경우 편집 전 유효 한도를 경계 레코드로
    /// 박아 전파를 차단한다. (이번 달/미래 편집은 forward 의미를 유지해야 하므로 setLimit을 그대로 쓴다.)
    @MainActor
    func setLimitForSingleMonth(_ limit: Int, for category: String, month: Int, in context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        ))
        let nextMonth = CategoryBudgetStore.nextMonthKey(month)
        let hasExplicitNext = records.contains { $0.effectiveFrom == nextMonth }
        // 편집 전, 다음 달에 유효하던 한도(없으면 0 = 한도 없음 → tombstone으로 복원).
        let carry = CategoryBudgetStore.resolveLimit(in: records, category: category, asOf: nextMonth) ?? 0

        try setLimit(limit, for: category, effectiveFrom: month, in: context)

        // 다음 달에 사용자 레코드가 없고, 새 값이 기존 전파값과 다를 때만 경계 레코드를 남긴다.
        if !hasExplicitNext && limit != carry {
            try setLimit(carry, for: category, effectiveFrom: nextMonth, in: context)
        }
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
