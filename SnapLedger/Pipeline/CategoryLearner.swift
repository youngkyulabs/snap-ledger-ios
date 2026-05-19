import Foundation
import SwiftData

struct CategoryLearner: Sendable {
    static func normalize(_ merchant: String) -> String {
        let toStrip = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        var result = ""
        for scalar in merchant.lowercased().unicodeScalars where !toStrip.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    func category(for merchant: String, in context: ModelContext) throws -> String? {
        let normalized = Self.normalize(merchant)
        let descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == normalized }
        )
        return try context.fetch(descriptor).first?.category
    }

    func learn(merchant: String, category: String, in context: ModelContext) throws {
        let normalized = Self.normalize(merchant)
        let descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == normalized }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.category = category
            existing.updatedAt = .now
        } else {
            context.insert(MerchantCategory(merchantNormalized: normalized, category: category))
        }
        try context.save()
    }
}
