import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "budget")

struct CategoryBudgetStore {
    /// Converts Date to integer month key (YYYYMM).
    static func monthKey(from date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return (comps.year ?? 0) * 100 + (comps.month ?? 0)
    }

    /// Converts an integer month key (YYYYMM) back to the first instant of that month.
    static func date(from key: Int, calendar: Calendar = .current) -> Date {
        var comps = DateComponents()
        comps.year = key / 100
        comps.month = key % 100
        comps.day = 1
        return calendar.date(from: comps) ?? Date()
    }

    /// Calculates next month integer key.
    static func nextMonthKey(_ key: Int) -> Int {
        let year = key / 100
        let month = key % 100
        return month >= 12 ? (year + 1) * 100 + 1 : key + 1
    }

    /// Calculates previous month integer key.
    static func previousMonthKey(_ key: Int) -> Int {
        let year = key / 100
        let month = key % 100
        return month <= 1 ? (year - 1) * 100 + 12 : key - 1
    }

    /// Resolves effective limit for a category in the specified month.
    static func resolveLimit(in budgets: [CategoryBudget], category: String, asOf month: Int) -> Int? {
        let effective = budgets
            .filter { $0.category == category && $0.effectiveFrom <= month }
            .max { $0.effectiveFrom < $1.effectiveFrom }
        guard let limit = effective?.monthlyLimit, limit > 0 else { return nil }
        return limit
    }

    /// Resolves all effective budget items as of the specified month.
    static func resolveAll(in budgets: [CategoryBudget], asOf month: Int, presets: [String]) -> [BudgetCSVRow] {
        let offList = Set(budgets.map { $0.category }).subtracting(presets).sorted()
        return (presets + offList).compactMap { category in
            guard let limit = resolveLimit(in: budgets, category: category, asOf: month) else { return nil }
            return BudgetCSVRow(category: category, limit: limit)
        }
    }

    /// Sums the effective limits of every category in the specified month; `overrides` replace stored limits (0 clears one).
    static func totalLimit(in budgets: [CategoryBudget], asOf month: Int, overrides: [String: Int] = [:]) -> Int {
        Set(budgets.map(\.category)).union(overrides.keys).reduce(0) { total, category in
            total + (overrides[category] ?? resolveLimit(in: budgets, category: category, asOf: month) ?? 0)
        }
    }

    /// Sets category limit starting from the specified month.
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

    /// Sets category limit for a single month, bounding subsequent carryover.
    @MainActor
    func setLimitForSingleMonth(_ limit: Int, for category: String, month: Int, in context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        ))
        let nextMonth = CategoryBudgetStore.nextMonthKey(month)
        let hasExplicitNext = records.contains { $0.effectiveFrom == nextMonth }
        // Look up effective limit for next month prior to edit.
        let carry = CategoryBudgetStore.resolveLimit(in: records, category: category, asOf: nextMonth) ?? 0

        try setLimit(limit, for: category, effectiveFrom: month, in: context)

        // Create boundary record for next month if needed to preserve carryover.
        if !hasExplicitNext && limit != carry {
            try setLimit(carry, for: category, effectiveFrom: nextMonth, in: context)
        }
    }

    /// Saves an edited limit: a past month changes only that month, later months carry it forward.
    /// Returns false without writing when the stored limit already matches.
    @MainActor
    @discardableResult
    func applyLimitEdit(
        _ limit: Int,
        for category: String,
        month: Int,
        currentMonth: Int,
        in context: ModelContext
    ) throws -> Bool {
        let records = try context.fetch(FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        ))
        guard limit != (Self.resolveLimit(in: records, category: category, asOf: month) ?? 0) else { return false }
        if month < currentMonth {
            try setLimitForSingleMonth(limit, for: category, month: month, in: context)
        } else {
            try setLimit(limit, for: category, effectiveFrom: month, in: context)
        }
        return true
    }

    /// Clears category limit starting from the specified month via tombstone.
    @MainActor
    func endBudget(for category: String, asOf month: Int, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.category == category }
        )
        let records = try context.fetch(descriptor)
        guard CategoryBudgetStore.resolveLimit(in: records, category: category, asOf: month) != nil else { return }
        try setLimit(0, for: category, effectiveFrom: month, in: context)
    }

    /// Exports budget CSV file for the affected month.
    @MainActor
    func exportBestEffort(month: Int, in context: ModelContext) {
        let key = SyncCoordinator.monthKeyString(from: month)
        do {
            try CSVFolderAccess.withFolder(in: context) { folderURL in
                try SyncCoordinator().exportBudgetMonths([key], folderURL: folderURL, in: context)
            }
        } catch CSVFolderAccess.AccessError.noCSVFolder {
            // Skip silently if no folder is configured.
        } catch {
            log.error("예산 CSV export(best-effort) failed: \(String(describing: error))")
        }
    }
}
