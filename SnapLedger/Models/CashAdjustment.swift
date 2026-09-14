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
    var id = UUID()
    /// Target month key (YYYYMM).
    var monthKey = 0
    var title = ""
    var direction = CashAdjustmentDirection.withdrawal
    var amount = 0
    /// Sort order index.
    var sortOrder = 0
    var note: String?

    init(
        id: UUID = UUID(),
        monthKey: Int,
        title: String,
        direction: CashAdjustmentDirection,
        amount: Int,
        sortOrder: Int = 0,
        note: String? = nil
    ) {
        self.id = id
        self.monthKey = monthKey
        self.title = title
        self.direction = direction
        self.amount = amount
        self.sortOrder = sortOrder
        self.note = note
    }
}
