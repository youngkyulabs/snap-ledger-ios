import SwiftUI
import SwiftData

struct EntryEditorView: View {
    private enum Field: Hashable {
        case merchant, category
    }

    @Bindable var entry: ParsedEntry
    var insertOnSave: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var saveError: String?
    @State private var confirmDelete = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") {
                    DatePicker("날짜", selection: $entry.date, displayedComponents: .date)
                    TextField("설명", text: $entry.merchant)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                    if !entry.merchantCandidates.isEmpty {
                        merchantCandidateChips
                    }
                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("0", value: amountBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("원").foregroundStyle(.secondary)
                    }
                    if !entry.amountCandidates.isEmpty {
                        amountCandidateChips
                    }
                }

                Section("카테고리") {
                    TextField("카테고리", text: categoryBinding)
                        .focused($focusedField, equals: .category)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                    presetChips
                }

                Section("메모") {
                    TextField("선택 사항", text: noteBinding, axis: .vertical)
                        .lineLimit(1...3)
                }

                if entry.confidence < 0.8 {
                    Section {
                        Label("신뢰도가 낮아요 — 값 확인 후 저장하세요.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("이 항목 삭제", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: entry.confidence < 0.8)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("저장", action: save)
                        .disabled(entry.merchant.isEmpty || entry.amount <= 0)
                }
            }
            .navigationTitle("검토")
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
                isPresented: $confirmDelete
            ) {
                Button("삭제", role: .destructive, action: performDelete)
                Button("취소", role: .cancel) { }
            } message: {
                Text("검토 목록에서 사라져요.")
            }
        }
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { entry.category ?? "" },
            set: { entry.category = $0.isEmpty ? nil : $0 }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { entry.note ?? "" },
            set: { entry.note = $0.isEmpty ? nil : $0 }
        )
    }

    private var amountBinding: Binding<Int?> {
        Binding(
            get: { entry.amount == 0 ? nil : entry.amount },
            set: { entry.amount = $0 ?? 0 }
        )
    }

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
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
                if let category = entry.category {
                    proxy.scrollTo("p:\(category)", anchor: .center)
                }
            }
            .onChange(of: entry.category) { _, new in
                guard let new else { return }
                withAnimation { proxy.scrollTo("p:\(new)", anchor: .center) }
            }
        }
    }

    private var merchantCandidateChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entry.merchantCandidates, id: \.self) { candidate in
                        candidateChip(
                            text: candidate,
                            isSelected: entry.merchant == candidate
                        ) {
                            entry.merchant = candidate
                        }
                        .id("m:\(candidate)")
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo("m:\(entry.merchant)", anchor: .center) }
            .onChange(of: entry.merchant) { _, new in
                withAnimation { proxy.scrollTo("m:\(new)", anchor: .center) }
            }
        }
    }

    private var amountCandidateChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entry.amountCandidates, id: \.self) { candidate in
                        candidateChip(
                            text: "\(candidate.formatted())원",
                            isSelected: entry.amount == candidate
                        ) {
                            entry.amount = candidate
                        }
                        .id("a:\(candidate)")
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo("a:\(entry.amount)", anchor: .center) }
            .onChange(of: entry.amount) { _, new in
                withAnimation { proxy.scrollTo("a:\(new)", anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func candidateChip(
        text: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isSelected {
            Button(action: action) {
                Label(text, systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button(text, action: action)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }

    @ViewBuilder
    private func presetChip(for preset: String) -> some View {
        let isSelected = entry.category == preset
        if isSelected {
            Button {
                entry.category = preset
            } label: {
                Label(preset, systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button(preset) { entry.category = preset }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }

    private func save() {
        if insertOnSave {
            modelContext.insert(entry)
        }
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner()).save(entry, in: modelContext)
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func performDelete() {
        if !insertOnSave {
            entry.status = .dismissed
            try? modelContext.save()
        }
        dismiss()
    }
}
