import Foundation
import SwiftData

@Model
final class MonthlyReconciliation {
    var id = UUID()
    /// Target month key (YYYYMM).
    var monthKey = 0
    var note: String?
    var updatedAt = Date.now

    init(
        id: UUID = UUID(),
        monthKey: Int,
        note: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthKey = monthKey
        self.note = note
        self.updatedAt = updatedAt
    }
}
