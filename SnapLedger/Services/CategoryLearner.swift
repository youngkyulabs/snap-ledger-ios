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

    /// Checks whether MerchantCategory is present in the container schema.
    private static func hasMerchantStore(_ context: ModelContext) -> Bool {
        context.container.schema.entities.contains { $0.name == "MerchantCategory" }
    }

    func category(for merchant: String, in context: ModelContext) throws -> String? {
        guard Self.hasMerchantStore(context) else { return nil }
        let normalized = Self.normalize(merchant)
        let descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == normalized }
        )
        return try context.fetch(descriptor)
            .max { $0.updatedAt < $1.updatedAt }?
            .category
    }

    func learn(merchant: String, category: String, in context: ModelContext) throws {
        guard Self.hasMerchantStore(context) else { return }
        let normalized = Self.normalize(merchant)
        let descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == normalized }
        )
        // Keep the newest record and remove older duplicates.
        let matches = try context.fetch(descriptor).sorted { $0.updatedAt > $1.updatedAt }
        if let keep = matches.first {
            keep.category = category
            keep.updatedAt = .now
            for extra in matches.dropFirst() {
                context.delete(extra)
            }
        } else {
            context.insert(MerchantCategory(merchantNormalized: normalized, category: category))
        }
        try context.save()
    }
}
