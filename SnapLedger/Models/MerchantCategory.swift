import Foundation
import SwiftData

@Model
final class MerchantCategory {
    var merchantNormalized = ""
    var category = ""
    var updatedAt = Date.now

    init(merchantNormalized: String, category: String, updatedAt: Date = .now) {
        self.merchantNormalized = merchantNormalized
        self.category = category
        self.updatedAt = updatedAt
    }
}
