import Foundation

/// Checks whether category is outside preset list.
enum CategoryValidation {
    static func isOffPreset(_ category: String?, presets: [String]) -> Bool {
        guard let category,
              !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return !presets.contains(category)
    }
}
