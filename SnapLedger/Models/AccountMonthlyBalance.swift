import Foundation
import SwiftData

@Model
final class AccountMonthlyBalance {
    var id: UUID
    /// YYYYMM (예: 202606)
    var monthKey: Int
    var accountName: String
    var sortOrder: Int
    var openingBalance: Int
    var closingBalance: Int
    var interestAmount: Int

    init(
        id: UUID = UUID(),
        monthKey: Int,
        accountName: String,
        sortOrder: Int = 0,
        openingBalance: Int = 0,
        closingBalance: Int = 0,
        interestAmount: Int = 0
    ) {
        self.id = id
        self.monthKey = monthKey
        self.accountName = accountName
        self.sortOrder = sortOrder
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.interestAmount = interestAmount
    }
}
