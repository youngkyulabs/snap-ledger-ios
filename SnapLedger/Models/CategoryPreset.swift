import Foundation
import SwiftData

/// Category preset item model.
@Model
final class CategoryPreset {
    var name: String = ""
    var sortOrder: Int = 0

    init(name: String = "", sortOrder: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
    }
}
