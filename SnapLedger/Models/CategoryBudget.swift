import Foundation
import SwiftData

@Model
final class CategoryBudget {
    var category: String = ""
    /// Monthly limit amount (0 indicates cancellation tombstone).
    var monthlyLimit: Int = 0
    /// Effective starting month (YYYYMM).
    var effectiveFrom: Int = 0
    var updatedAt = Date.now

    init(category: String, monthlyLimit: Int, effectiveFrom: Int, updatedAt: Date = .now) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.effectiveFrom = effectiveFrom
        self.updatedAt = updatedAt
    }
}
