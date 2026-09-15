import Foundation
import SwiftData

/// Manages category preset records and syncs with local cache.
@MainActor
struct CategoryPresetStore {
    private func sortedPresets(in cloud: ModelContext) -> [CategoryPreset] {
        let all = (try? cloud.fetch(FetchDescriptor<CategoryPreset>())) ?? []
        return all.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns category names ordered by sortOrder.
    func currentNames(in cloud: ModelContext) -> [String] {
        sortedPresets(in: cloud).map(\.name)
    }

    /// Appends a new category preset.
    func add(_ name: String, in cloud: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let presets = sortedPresets(in: cloud)
        guard !presets.contains(where: { $0.name == trimmed }) else { return }
        let nextOrder = (presets.map(\.sortOrder).max() ?? -1) + 1
        cloud.insert(CategoryPreset(name: trimmed, sortOrder: nextOrder))
        try? cloud.save()
    }

    /// Deletes the category preset with the specified name.
    func remove(_ name: String, in cloud: ModelContext) {
        for preset in sortedPresets(in: cloud) where preset.name == name {
            cloud.delete(preset)
        }
        try? cloud.save()
    }

    /// Reorders category presets by name list.
    func reorder(_ orderedNames: [String], in cloud: ModelContext) {
        let byName = Dictionary(
            sortedPresets(in: cloud).map { ($0.name, $0) }
        ) { first, _ in first }
        for (index, name) in orderedNames.enumerated() {
            byName[name]?.sortOrder = index
        }
        try? cloud.save()
    }

    /// Syncs local AppSettings cache with the latest presets.
    func refreshCache(cloud: ModelContext, local: ModelContext) {
        let names = currentNames(in: cloud)
        guard let settings = try? local.fetch(FetchDescriptor<AppSettings>()).first else { return }
        settings.categoryPresets = names
        try? local.save()
    }
}
