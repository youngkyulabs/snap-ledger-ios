import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "presets")

/// Manages category preset records and syncs with local cache.
@MainActor
struct CategoryPresetStore {
    private func sortedPresets(in cloud: ModelContext) throws -> [CategoryPreset] {
        try cloud.fetch(FetchDescriptor<CategoryPreset>())
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns category names ordered by sortOrder.
    func currentNames(in cloud: ModelContext) throws -> [String] {
        try sortedPresets(in: cloud).map(\.name)
    }

    /// Appends a new category preset.
    func add(_ name: String, in cloud: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let presets = try sortedPresets(in: cloud)
            guard !presets.contains(where: { $0.name == trimmed }) else { return }
            let nextOrder = (presets.map(\.sortOrder).max() ?? -1) + 1
            cloud.insert(CategoryPreset(name: trimmed, sortOrder: nextOrder))
            try cloud.save()
        } catch {
            log.error("preset add failed: \(String(describing: error))")
        }
    }

    /// Deletes the category preset with the specified name.
    func remove(_ name: String, in cloud: ModelContext) {
        do {
            for preset in try sortedPresets(in: cloud) where preset.name == name {
                cloud.delete(preset)
            }
            try cloud.save()
        } catch {
            log.error("preset remove failed: \(String(describing: error))")
        }
    }

    /// Reorders category presets by name list.
    func reorder(_ orderedNames: [String], in cloud: ModelContext) {
        do {
            let byName = Dictionary(
                try sortedPresets(in: cloud).map { ($0.name, $0) }
            ) { first, _ in first }
            for (index, name) in orderedNames.enumerated() {
                byName[name]?.sortOrder = index
            }
            try cloud.save()
        } catch {
            log.error("preset reorder failed: \(String(describing: error))")
        }
    }

    /// Syncs local AppSettings cache with the latest presets; a failed read leaves the cache untouched.
    func refreshCache(cloud: ModelContext, local: ModelContext) {
        do {
            // Until presets migrate, the cloud list is not authoritative and the cache still seeds the migration.
            guard let settings = try local.fetch(FetchDescriptor<AppSettings>()).first,
                  settings.hasMigratedToCloudStore else { return }
            settings.categoryPresets = try currentNames(in: cloud)
            try local.save()
        } catch {
            log.error("preset cache refresh failed: \(String(describing: error))")
        }
    }
}
