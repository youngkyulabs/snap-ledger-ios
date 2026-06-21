import Foundation
import SwiftData

@Model
final class AccountMonthlyBalance {
    var id = UUID()
    /// YYYYMM (예: 202606)
    var monthKey = 0
    var accountName = ""
    var sortOrder = 0
    var openingBalance = 0
    var closingBalance = 0
    var interestAmount = 0

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
