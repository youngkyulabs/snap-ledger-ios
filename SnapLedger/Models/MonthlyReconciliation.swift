import Foundation
import SwiftData

@Model
final class MonthlyReconciliation {
    var id: UUID
    /// YYYYMM (예: 202606)
    var monthKey: Int
    var salaryAmount: Int
    var creditCardAmount: Int
    var savingsAmount: Int
    var note: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        monthKey: Int,
        salaryAmount: Int = 0,
        creditCardAmount: Int = 0,
        savingsAmount: Int = 0,
        note: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthKey = monthKey
        self.salaryAmount = salaryAmount
        self.creditCardAmount = creditCardAmount
        self.savingsAmount = savingsAmount
        self.note = note
        self.updatedAt = updatedAt
    }
}
