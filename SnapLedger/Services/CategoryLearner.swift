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
        return try context.fetch(descriptor)
            .max { $0.updatedAt < $1.updatedAt }?
            .category
    }

    func learn(merchant: String, category: String, in context: ModelContext) throws {
        let normalized = Self.normalize(merchant)
        let descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == normalized }
        )
        // CloudKit 다기기 동시 학습이 같은 가맹점에 중복 레코드를 만들 수 있다.
        // 최신 1개만 남겨 갱신하고 나머지는 병합 삭제(lazy dedup).
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
