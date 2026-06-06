import SwiftUI
import SwiftData

struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @FocusState private var guideFocused: Bool

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
        ScrollViewReader { proxy in
            Form {
                extractionGuideSection
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                if guideFocused {
                    HStack {
                        Spacer()
                        Button {
                            guideFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .padding(4)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("키보드 닫기")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("고급 설정")
            .onChange(of: guideFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("extractionGuide", anchor: .center) }
                }
            }
        }
    }

    private var extractionGuideSection: some View {
        Section {
            TextEditor(text: extractionGuideBinding)
                .frame(minHeight: 100)
                .font(.body)
                .focused($guideFocused)
                .id("extractionGuide")
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
