import Foundation
import SwiftData

enum ParsedEntryStatus: String, Codable, Sendable {
    case pending
    case dismissed
}

@Model
final class ParsedEntry {
    var id: UUID
    var date: Date
    var amount: Int
    var merchant: String
    var category: String?
    var note: String?
    var sourceImagePath: String?
    var confidence: Double
    var createdAt: Date
    var status: ParsedEntryStatus
    var merchantCandidates: [String] = []
    var amountCandidates: [Int] = []

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Int,
        merchant: String,
        category: String? = nil,
        note: String? = nil,
        sourceImagePath: String? = nil,
        confidence: Double = 1.0,
        createdAt: Date = .now,
        status: ParsedEntryStatus = .pending,
        merchantCandidates: [String] = [],
        amountCandidates: [Int] = []
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.note = note
        self.sourceImagePath = sourceImagePath
        self.confidence = confidence
        self.createdAt = createdAt
        self.status = status
        self.merchantCandidates = merchantCandidates
        self.amountCandidates = amountCandidates
    }
}
