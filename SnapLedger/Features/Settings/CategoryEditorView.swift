import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @State private var newCategoryText = ""
    @FocusState private var addFieldFocused: Bool

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    private var presets: [String] { settings.categoryPresets }

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
    }

    private var canAddCategory: Bool {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !presets.contains(trimmed)
    }

    private func addCategory() {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.categoryPresets.contains(trimmed) else {
            newCategoryText = ""
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.append(trimmed)
            try? modelContext.save()
            newCategoryText = ""
        }
    }

    private func deleteCategory(at offsets: IndexSet) {
        let removed = offsets.map { settings.categoryPresets[$0] }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.remove(atOffsets: offsets)
            try? modelContext.save()
        }
        // 삭제된 카테고리의 예산은 이번 달부터 해제(지난 달 한도는 보존).
        let currentMonthKey = CategoryBudgetStore.monthKey(from: Date())
        let store = CategoryBudgetStore()
        for category in removed {
            try? store.endBudget(for: category, asOf: currentMonthKey, in: modelContext)
        }
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            settings.categoryPresets.move(fromOffsets: source, toOffset: destination)
            try? modelContext.save()
        }
    }
}

#Preview {
    NavigationStack {
        CategoryEditorView()
    }
    .modelContainer(for: AppSettings.self, inMemory: true)
}
