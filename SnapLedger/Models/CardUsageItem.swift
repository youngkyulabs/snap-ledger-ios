import Foundation
import SwiftData

@Model
final class CardUsageItem {
    var id = UUID()
    /// Target month key (YYYYMM).
    var monthKey = 0
    var title = ""
    var amount = 0
    /// Prior month's bill withdrawn during this month. Default required so lightweight migration
    /// backfills pre-existing rows with 0.
    var previousAmount = 0
    var sortOrder = 0
    var updatedAt = Date.now

    init(
        id: UUID = UUID(),
        monthKey: Int,
        title: String,
        amount: Int,
        previousAmount: Int = 0,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthKey = monthKey
        self.title = title
        self.amount = amount
        self.previousAmount = previousAmount
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}
