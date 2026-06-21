import Foundation
import SwiftData

/// 카테고리 프리셋의 단일 진실원(`CategoryPreset` 레코드) CRUD + 로컬 캐시 동기화.
/// 캐시(`AppSettings.categoryPresets`)는 인텐트·읽기 지점이 빠르게 읽는 사본이다.
@MainActor
struct CategoryPresetStore {
    private func sortedPresets(in cloud: ModelContext) -> [CategoryPreset] {
        let all = (try? cloud.fetch(FetchDescriptor<CategoryPreset>())) ?? []
        return all.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// `sortOrder` 오름차순 이름 배열.
    func currentNames(in cloud: ModelContext) -> [String] {
        sortedPresets(in: cloud).map(\.name)
    }

    /// 새 프리셋을 끝에 추가. 빈 문자열·중복 이름은 무시.
    func add(_ name: String, in cloud: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let presets = sortedPresets(in: cloud)
        guard !presets.contains(where: { $0.name == trimmed }) else { return }
        let nextOrder = (presets.map(\.sortOrder).max() ?? -1) + 1
        cloud.insert(CategoryPreset(name: trimmed, sortOrder: nextOrder))
        try? cloud.save()
    }

    /// 해당 이름 프리셋 삭제(동명 레코드가 여럿이면 모두).
    func remove(_ name: String, in cloud: ModelContext) {
        for preset in sortedPresets(in: cloud) where preset.name == name {
            cloud.delete(preset)
        }
        try? cloud.save()
    }

    /// 주어진 이름 순서대로 `sortOrder`를 0..<n으로 재할당.
    func reorder(_ orderedNames: [String], in cloud: ModelContext) {
        let byName = Dictionary(
            sortedPresets(in: cloud).map { ($0.name, $0) }
        ) { first, _ in first }
        for (index, name) in orderedNames.enumerated() {
            byName[name]?.sortOrder = index
        }
        try? cloud.save()
    }

    /// 진실원(레코드) → 로컬 캐시(`AppSettings.categoryPresets`)로 동기화.
    /// 원격 기기 변경 반영 + 편집 직후 호출.
    func refreshCache(cloud: ModelContext, local: ModelContext) {
        let names = currentNames(in: cloud)
        guard let settings = try? local.fetch(FetchDescriptor<AppSettings>()).first else { return }
        settings.categoryPresets = names
        try? local.save()
    }
}
