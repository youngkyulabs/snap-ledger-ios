import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CategoryPreset.sortOrder) private var presetRecords: [CategoryPreset]
    @Query private var settingsList: [AppSettings]
    @State private var newCategoryText = ""
    @FocusState private var addFieldFocused: Bool

    private let store = CategoryPresetStore()

    private var presets: [String] { presetRecords.map(\.name) }

    private var settings: AppSettings {
        if let existing = settingsList.first { return existing }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { category in
                    Text(category)
                }
                .onDelete(perform: deleteCategory)
                .onMove(perform: moveCategory)

                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(canAddCategory ? Color.accentColor : Color.secondary)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: canAddCategory)
                    TextField("새 카테고리 이름", text: $newCategoryText)
                        .submitLabel(.done)
                        .focused($addFieldFocused)
                        .onSubmit(addCategory)
                    if canAddCategory {
                        Button("추가", action: addCategory)
                            .buttonStyle(.borderless)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: canAddCategory)
            } header: {
                Text("카테고리")
            } footer: {
                Text("추출·통계·예산에서 함께 쓰는 카테고리예요. 삭제하면 이번 달부터 예산에서 빠지고, 지난 달 기록은 그대로 남아요.")
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("카테고리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !presets.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        // 화면 진입 시 원격 기기 변경을 캐시에 반영.
        .task { store.refreshCache(cloud: modelContext, local: modelContext) }
    }

    private var canAddCategory: Bool {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !presets.contains(trimmed)
    }

    private func addCategory() {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !presets.contains(trimmed) else {
            newCategoryText = ""
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            store.add(trimmed, in: modelContext)
            store.refreshCache(cloud: modelContext, local: modelContext)
            newCategoryText = ""
        }
    }

    private func deleteCategory(at offsets: IndexSet) {
        let removed = offsets.map { presets[$0] }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            for name in removed {
                store.remove(name, in: modelContext)
            }
            store.refreshCache(cloud: modelContext, local: modelContext)
        }
        // 삭제된 카테고리의 예산은 이번 달부터 해제(지난 달 한도는 보존).
        let currentMonthKey = CategoryBudgetStore.monthKey(from: Date())
        let budgetStore = CategoryBudgetStore()
        for category in removed {
            try? budgetStore.endBudget(for: category, asOf: currentMonthKey, in: modelContext)
        }
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var names = presets
        names.move(fromOffsets: source, toOffset: destination)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            store.reorder(names, in: modelContext)
            store.refreshCache(cloud: modelContext, local: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryEditorView()
    }
    .modelContainer(for: [CategoryPreset.self, AppSettings.self, CategoryBudget.self], inMemory: true)
}
