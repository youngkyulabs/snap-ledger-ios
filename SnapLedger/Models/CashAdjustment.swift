import Foundation
import SwiftData

enum CashAdjustmentDirection: String, Codable, CaseIterable, Sendable {
    case deposit
    case withdrawal

    var label: String {
        switch self {
        case .deposit: "입금"
        case .withdrawal: "출금"
        }
    }

    static func from(label: String) -> CashAdjustmentDirection? {
        switch label {
        case "입금": .deposit
        case "출금": .withdrawal
        default: nil
        }
    }
}

@Model
final class CashAdjustment {
    var id: UUID
    /// YYYYMM (예: 202606)
    var monthKey: Int
    var date: Date
    var title: String
    var direction: CashAdjustmentDirection
    var amount: Int
    var note: String?

    init(
        id: UUID = UUID(),
        monthKey: Int,
        date: Date,
        title: String,
        direction: CashAdjustmentDirection,
        amount: Int,
        note: String? = nil
    ) {
        self.id = id
        self.monthKey = monthKey
        self.date = date
        self.title = title
        self.direction = direction
        self.amount = amount
        self.note = note
    }
}
