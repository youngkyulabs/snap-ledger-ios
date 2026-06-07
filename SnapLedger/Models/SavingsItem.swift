import Foundation
import SwiftData

@Model
final class SavingsItem {
    var id: UUID
    /// YYYYMM (예: 202606)
    var monthKey: Int
    var title: String
    var amount: Int
    var sortOrder: Int
    var updatedAt: Date

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
