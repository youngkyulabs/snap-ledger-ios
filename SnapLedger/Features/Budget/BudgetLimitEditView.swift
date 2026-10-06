import SwiftUI
import SwiftData

struct BudgetLimitEditView: View {
    let month: Int
    let currentMonthKey: Int
    var focusCategory: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]
    @Query private var budgets: [CategoryBudget]
    @FocusState private var focusedCategory: String?
    /// Typed limits not saved yet, by category; 0 clears the limit.
    @State private var drafts: [String: Int] = [:]
    @State private var saveError: String?

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }
    private var isForwardMonth: Bool { month >= currentMonthKey }
    private var totalLimit: Int { CategoryBudgetStore.totalLimit(in: budgets, asOf: month, overrides: drafts) }

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        TextField("0", value: limitValue(for: category), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .focused($focusedCategory, equals: category)
                        Text("원").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("\(ledgerMonthLabel(month)) 한도").textCase(nil)
            } footer: {
                if isForwardMonth {
                    Text("이 달부터 적용되고, 이후 달에도 자동으로 반복돼요. 비워두면 한도가 없어요.")
                } else {
                    Text("이 달에만 적용돼요. 다른 달의 한도는 그대로 유지돼요.")
                }
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        // An inset, not an overlay, so the focused bottom row is not hidden behind the button.
        .safeAreaInset(edge: .bottom) {
            if focusedCategory != nil {
                HStack {
                    Spacer()
                    Button {
                        focusedCategory = nil
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
        .navigationTitle("한도 편집")
        .navigationSubtitle("총 예산 \(totalLimit.formatted(.number))원")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedCategory = focusCategory }
        // Save a field once its editing ends rather than on every keystroke.
        .onChange(of: focusedCategory) { previous, _ in
            if let previous { commit(previous) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commitAll() }
        }
        .onDisappear { commitAll() }
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
    }

    // Value-based TextField writes through on every keystroke, so typing only updates the draft.
    private func limitValue(for category: String) -> Binding<Int?> {
        Binding(
            get: {
                if let draft = drafts[category] { return draft > 0 ? draft : nil }
                return CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month)
            },
            set: { drafts[category] = max($0 ?? 0, 0) }
        )
    }

    private func commit(_ category: String) {
        guard let amount = drafts[category] else { return }
        defer { drafts[category] = nil }
        let store = CategoryBudgetStore()
        do {
            if try store.applyLimitEdit(
                amount, for: category, month: month, currentMonth: currentMonthKey, in: modelContext
            ) {
                store.exportBestEffort(month: month, in: modelContext)
            }
        } catch {
            saveError = "한도를 저장하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func commitAll() {
        for category in drafts.keys.sorted() {
            commit(category)
        }
    }
}
