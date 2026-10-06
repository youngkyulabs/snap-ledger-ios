import SwiftUI
import SwiftData

struct BudgetLimitEditView: View {
    let month: Int
    let currentMonthKey: Int
    var focusCategory: String?

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var budgets: [CategoryBudget]
    @FocusState private var focusedCategory: String?
    @State private var saveError: String?

    private var presets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }
    private var isForwardMonth: Bool { month >= currentMonthKey }
    private var totalLimit: Int { CategoryBudgetStore.totalLimit(in: budgets, asOf: month) }

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
                Text("카테고리별 한도").textCase(nil)
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
        .navigationSubtitle("\(ledgerMonthLabel(month)) 총 예산 \(totalLimit.formatted(.number))원")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedCategory = focusCategory }
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

    // Value-based TextField writes through on every keystroke.
    private func limitValue(for category: String) -> Binding<Int?> {
        Binding(
            get: { CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month) },
            set: { newValue in
                let amount = max(newValue ?? 0, 0)
                let current = CategoryBudgetStore.resolveLimit(in: budgets, category: category, asOf: month) ?? 0
                guard amount != current else { return }
                let store = CategoryBudgetStore()
                do {
                    if month < currentMonthKey {
                        // Past months apply single-month edit.
                        try store.setLimitForSingleMonth(amount, for: category, month: month, in: modelContext)
                    } else {
                        // Current/future months carry forward.
                        try store.setLimit(amount, for: category, effectiveFrom: month, in: modelContext)
                    }
                    store.exportBestEffort(month: month, in: modelContext)
                } catch {
                    saveError = "한도를 저장하지 못했어요. 다시 시도해 주세요."
                }
            }
        )
    }
}
