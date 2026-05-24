import SwiftUI
import SwiftData

struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var newCategoryText = ""

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        Form {
            categoriesSection
            extractionGuideSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("고급 설정")
        .toolbar {
            if !settings.categoryPresets.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(settings.categoryPresets, id: \.self) { preset in
                Text(preset)
            }
            .onDelete(perform: deleteCategoryPresets)
            .onMove(perform: moveCategoryPresets)

            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(canAddCategory ? Color.accentColor : Color.secondary)
                    .animation(.smooth(duration: 0.2), value: canAddCategory)
                TextField("새 카테고리 추가", text: $newCategoryText)
                    .submitLabel(.done)
                    .onSubmit(addCategoryPreset)
                if canAddCategory {
                    Button("추가", action: addCategoryPreset)
                        .buttonStyle(.borderless)
                }
            }
            .animation(.smooth(duration: 0.2), value: canAddCategory)
        } header: {
            Text("카테고리")
        } footer: {
            Text("지출을 분류할 카테고리예요. 왼쪽으로 밀어 삭제하거나, 편집 모드에서 끌어 옮길 수 있어요.")
        }
    }

    private var canAddCategory: Bool {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !settings.categoryPresets.contains(trimmed)
    }

    private func addCategoryPreset() {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.categoryPresets.contains(trimmed) else {
            newCategoryText = ""
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            settings.categoryPresets.append(trimmed)
            try? modelContext.save()
            newCategoryText = ""
        }
    }

    private func deleteCategoryPresets(at offsets: IndexSet) {
        withAnimation(.smooth(duration: 0.3)) {
            settings.categoryPresets.remove(atOffsets: offsets)
            try? modelContext.save()
        }
    }

    private func moveCategoryPresets(from source: IndexSet, to destination: Int) {
        withAnimation(.smooth(duration: 0.3)) {
            settings.categoryPresets.move(fromOffsets: source, toOffset: destination)
            try? modelContext.save()
        }
    }

    private var extractionGuideSection: some View {
        Section {
            TextEditor(text: extractionGuideBinding)
                .frame(minHeight: 100)
                .font(.body)
        } header: {
            Text("추출 가이드 (선택)")
        } footer: {
            Text("자주 쓰는 카드사 형식이나 추출 오류 패턴을 적어주세요. 사진에서 자동 추출할 때 기본 규칙보다 먼저 참고해요.")
        }
    }

    private var extractionGuideBinding: Binding<String> {
        Binding(
            get: { settings.customExtractionGuide },
            set: { newValue in
                settings.customExtractionGuide = newValue
                try? modelContext.save()
            }
        )
    }
}

#Preview {
    NavigationStack {
        AdvancedSettingsView()
    }
    .modelContainer(for: AppSettings.self, inMemory: true)
}
