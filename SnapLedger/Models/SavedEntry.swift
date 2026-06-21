import Foundation
import SwiftData

@Model
final class SavedEntry {
    var id = UUID()
    var date = Date.distantPast
    var amount = 0
    var merchant = ""
    var category: String?
    var note: String?
    var savedAt = Date.distantPast
    var csvFile = ""

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
