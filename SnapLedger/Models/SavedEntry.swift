import Foundation
import SwiftData

@Model
final class SavedEntry {
    var id: UUID
    var date: Date
    var amount: Int
    var merchant: String
    var category: String?
    var note: String?
    var savedAt: Date
    var csvFile: String

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Int,
        merchant: String,
        category: String? = nil,
        note: String? = nil,
        savedAt: Date = .now,
        csvFile: String
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.note = note
        self.savedAt = savedAt
        self.csvFile = csvFile
    }
}
