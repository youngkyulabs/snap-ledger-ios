import Foundation
import SwiftData
import Testing
@testable import SnapLedger

@MainActor
struct CategoryPresetStoreTests {
    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CategoryPreset.self, CategoryBudget.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func localContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func addAppendsInOrderAndIgnoresDuplicates() throws {
        let cloud = try cloudContext()
        let store = CategoryPresetStore()
        store.add("식비", in: cloud)
        store.add("카페", in: cloud)
        store.add("식비", in: cloud) // 중복 무시
        #expect(store.currentNames(in: cloud) == ["식비", "카페"])
    }

    @Test func removeDeletesRecord() throws {
        let cloud = try cloudContext()
        let store = CategoryPresetStore()
        store.add("식비", in: cloud)
        store.add("카페", in: cloud)
        store.remove("식비", in: cloud)
        #expect(store.currentNames(in: cloud) == ["카페"])
    }

    @Test func reorderReassignsSortOrder() throws {
        let cloud = try cloudContext()
        let store = CategoryPresetStore()
        store.add("식비", in: cloud)
        store.add("카페", in: cloud)
        store.add("교통", in: cloud)
        store.reorder(["교통", "식비", "카페"], in: cloud)
        #expect(store.currentNames(in: cloud) == ["교통", "식비", "카페"])
    }

    @Test func refreshCacheWritesNamesIntoSettings() throws {
        let cloud = try cloudContext()
        let local = try localContext()
        let settings = AppSettings(categoryPresets: [])
        local.insert(settings)
        try local.save()

        let store = CategoryPresetStore()
        store.add("식비", in: cloud)
        store.add("카페", in: cloud)
        store.refreshCache(cloud: cloud, local: local)

        let fetched = try local.fetch(FetchDescriptor<AppSettings>()).first
        #expect(fetched?.categoryPresets == ["식비", "카페"])
    }
}
