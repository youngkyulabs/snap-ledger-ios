import SwiftUI
import SwiftData

struct SavedEntryEditorView: View {
    private enum Field: Hashable {
        case merchant, amount, category, note
    }

    let entry: SavedEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]

    @State private var date: Date
    @State private var merchant: String
    @State private var amount: Int
    @State private var category: String
    @State private var note: String
    @State private var saveError: String?
    @State private var showDeleteConfirm = false
    @FocusState private var focusedField: Field?

    private let originalDate: Date

    init(entry: SavedEntry) {
        self.entry = entry
        self.originalDate = entry.date
        self._date = State(initialValue: entry.date)
        self._merchant = State(initialValue: entry.merchant)
        self._amount = State(initialValue: entry.amount)
        self._category = State(initialValue: entry.category ?? "")
        self._note = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("내용") {
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                    TextField("설명", text: $merchant)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .id(Field.merchant)
                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("0", value: amountBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .amount)
                        Text("원").foregroundStyle(.secondary)
                    }
                    .id(Field.amount)
                }

                Section("카테고리") {
                    TextField("카테고리", text: $category)
                        .focused($focusedField, equals: .category)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .id(Field.category)
                    presetChips
                    if isOffPreset {
                        offPresetWarning
                            .transition(.opacity)
                    }
                }

                Section("메모") {
                    TextField("선택 사항", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .note)
                        .id(Field.note)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("이 항목 삭제", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isOffPreset)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button {
                            focusedField = nil
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("저장", action: save)
                        .disabled(!EntrySaveValidation.canSaveEdit(merchant: merchant, amount: amount))
                }
            }
            .navigationTitle("편집")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "저장 실패",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                ),
                presenting: saveError
            ) { _ in
                Button("확인", role: .cancel) { saveError = nil }
            } message: { message in
                Text(message)
            }
            .alert(
                "이 항목을 삭제할까요?",
                isPresented: $showDeleteConfirm
            ) {
                Button("삭제", role: .destructive, action: delete)
                Button("취소", role: .cancel) { }
            } message: {
                Text("삭제하면 되돌릴 수 없어요.")
            }
            .onChange(of: focusedField) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            }
        }
    }

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    private var isOffPreset: Bool {
        CategoryValidation.isOffPreset(category, presets: presets)
    }

    private var amountBinding: Binding<Int?> {
        Binding(
            get: { amount == 0 ? nil : amount },
            set: { amount = $0 ?? 0 }
        )
    }

    private var presetChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        presetChip(for: preset)
                            .id("p:\(preset)")
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                if !category.isEmpty {
                    proxy.scrollTo("p:\(category)", anchor: .center)
                }
            }
            .onChange(of: category) { _, new in
                guard !new.isEmpty else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("p:\(new)", anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func presetChip(for preset: String) -> some View {
        let isSelected = category == preset
        Button {
            category = preset
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(preset)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .background {
                Capsule().fill(
                    isSelected ? Color.accentColor : Color.accentColor.opacity(0.15)
                )
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var offPresetWarning: some View {
        Label("목록에 없는 카테고리예요.", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }

    private func save() {
        // entry는 여기서 바꾸지 않는다 — update가 쓰기 성공 시에만 대입한다 (실패 시 더티 방지).
        let edit = SavedEntryEdit(
            date: date,
            merchant: merchant,
            amount: amount,
            category: category.isEmpty ? nil : category,
            note: note.isEmpty ? nil : note
        )
        performUpdate(edit)
    }

    private func performUpdate(_ edit: SavedEntryEdit) {
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner())
                .update(entry, to: edit, in: modelContext)
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func delete() {
        performDelete()
    }

    private func performDelete() {
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner())
                .delete(entry, originalDate: originalDate, in: modelContext)
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
