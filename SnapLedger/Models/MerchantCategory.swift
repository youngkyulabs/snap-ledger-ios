import Foundation
import SwiftData

@Model
final class MerchantCategory {
    @Attribute(.unique) var merchantNormalized: String
    var category: String
    var updatedAt: Date

    init(merchantNormalized: String, category: String, updatedAt: Date = .now) {
        self.merchantNormalized = merchantNormalized
        self.category = category
        self.updatedAt = updatedAt
    }
}
