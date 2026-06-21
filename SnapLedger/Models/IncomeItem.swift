import Foundation
import SwiftData

@Model
final class IncomeItem {
    var id = UUID()
    /// YYYYMM (예: 202606)
    var monthKey = 0
    var title = ""
    var amount = 0
    var sortOrder = 0
    var updatedAt = Date.now

    init(
        id: UUID = UUID(),
        monthKey: Int,
        title: String,
        amount: Int,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthKey = monthKey
        self.title = title
        self.amount = amount
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}
