import Foundation
import SwiftUI
import SwiftData

struct EntryEditorView: View {
    private enum Field: Hashable {
        case merchant, amount, category, note
    }

    @Bindable var entry: ParsedEntry
    var insertOnSave: Bool = false
    /// Callback invoked after entry is successfully saved.
    var onSaved: ((BudgetProgress.Line?) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]

    @State private var saveError: String?
    @State private var confirmDelete = false
    /// Warning text shown when the entry lands in an already-reconciled month.
    @State private var reconciledWarning: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                if let sourceImageFilename {
                    Section(InboxPayload.isText(filename: sourceImageFilename) ? "공유한 내용" : "원본 이미지") {
                        InboxImageView(filename: sourceImageFilename)
                            .frame(maxWidth: .infinity, maxHeight: 320)
                    }
                }

                Section("내용") {
                    dateRow
                    TextField("설명", text: $entry.merchant)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .id(Field.merchant)
                    if !entry.merchantCandidates.isEmpty {
                        merchantCandidateChips
                    }
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
                    if !entry.amountCandidates.isEmpty {
                        amountCandidateChips
                    }
                }

                Section("카테고리") {
                    TextField("카테고리", text: categoryBinding)
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
                    TextField("선택 사항", text: noteBinding, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .note)
                        .id(Field.note)
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
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: entry.confidence < 0.8)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isOffPreset)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: dateStatus.isWarning)
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
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("저장", action: save)
                        .disabled(!EntrySaveValidation.canSaveReview(merchant: entry.merchant, amount: entry.amount))
                }
            }
            .navigationTitle(insertOnSave ? "수동 입력" : "검토")
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
                "정산이 끝난 달이에요",
                isPresented: Binding(
                    get: { reconciledWarning != nil },
                    set: { if !$0 { reconciledWarning = nil } }
                ),
                presenting: reconciledWarning
            ) { _ in
                Button("추가") {
                    reconciledWarning = nil
                    performSave()
                }
                Button("취소", role: .cancel) { reconciledWarning = nil }
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
            .onChange(of: focusedField) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            }
        }
    }

    /// Source image filename if still present in inbox.
    private var sourceImageFilename: String? {
        guard let name = entry.sourceImagePath else { return nil }
        let url = AppGroup.inboxURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? name : nil
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

    private var isOffPreset: Bool {
        CategoryValidation.isOffPreset(entry.category, presets: presets)
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
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("p:\(new)", anchor: .center) }
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
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("m:\(new)", anchor: .center) }
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
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("a:\(new)", anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func candidateChip(
        text: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(text)
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

    @ViewBuilder
    private func presetChip(for preset: String) -> some View {
        let isSelected = entry.category == preset
        Button {
            entry.category = preset
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
        NotificationScheduler().clearDelivered()
        // Confirm before altering a month the user already reconciled. Insertion is deferred to
        // `performSave` so that cancelling leaves no stray row behind.
        if let warning = ReconciledMonthGuard.warningMessage(for: entry.date, in: modelContext) {
            reconciledWarning = warning
            return
        }
        performSave()
    }

    private func performSave() {
        if insertOnSave {
            modelContext.insert(entry)
        }
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner())
                .save(entry, in: modelContext)
            onSaved?(BudgetProgress.thresholdLine(for: entry, in: modelContext))
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

// MARK: - Date Warning (Review Popup)
private extension EntryEditorView {
    /// Review date status classification.
    var dateStatus: ReviewDateStatus {
        ReviewDateCheck.status(for: entry.date, now: entry.createdAt)
    }

    /// Accessibility label for date warning icon.
    var dateWarningLabel: String? {
        switch dateStatus {
        case .tooOld: return "날짜가 예상보다 오래됐어요 — 확인해 주세요."
        case .future: return "날짜가 미래로 되어 있어요 — 확인해 주세요."
        case .today, .yesterday: return nil
        }
    }

    /// Date picker row view.
    var dateRow: some View {
        HStack {
            // Visual label (accessibility handled by DatePicker)
            Text("날짜")
                .accessibilityHidden(true)
            Spacer()
            if let dateWarningLabel {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(dateWarningLabel)
            }
            DatePicker("날짜", selection: $entry.date, displayedComponents: .date)
                .labelsHidden()
        }
    }
}
