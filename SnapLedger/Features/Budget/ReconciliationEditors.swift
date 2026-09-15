import SwiftUI

// MARK: - Item Editor Sheet (Income, Savings, Card Usage)

struct ReconciliationItemEditor: View {
    let navTitle: String
    let titlePlaceholder: String
    let onSave: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var amount: Int

    init(
        navTitle: String,
        titlePlaceholder: String,
        initialTitle: String,
        initialAmount: Int,
        onSave: @escaping (String, Int) -> Void
    ) {
        self.navTitle = navTitle
        self.titlePlaceholder = titlePlaceholder
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _amount = State(initialValue: initialAmount)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                TextField(titlePlaceholder, text: $title)
                reconciliationMoneyField("금액", value: $amount)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    onSave(trimmedTitle, amount)
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty)
            }
        }
    }
}

// MARK: - Card Usage Editor Sheet

struct ReconciliationCardEditor: View {
    let initial: CardUsageItemDraft?
    let onSave: (String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var amount: Int
    @State private var previousAmount: Int

    init(initial: CardUsageItemDraft?, onSave: @escaping (String, Int, Int) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _amount = State(initialValue: initial?.amount ?? 0)
        _previousAmount = State(initialValue: initial?.previousAmount ?? 0)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                TextField("카드명", text: $title)
            }
            Section {
                reconciliationMoneyField("이번 달 사용액", value: $amount)
            } footer: {
                Text("이번 달에 이 카드로 결제한 금액이에요.")
            }
            Section {
                reconciliationMoneyField("전월 사용액", value: $previousAmount)
            } footer: {
                Text("이번 달 계좌에서 빠져나간 지난달 카드대금이에요. 자금변동에 따로 넣지 않아도 돼요.")
            }
        }
        .navigationTitle(initial == nil ? "카드 추가" : "카드 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    onSave(trimmedTitle, amount, previousAmount)
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty)
            }
        }
    }
}

// MARK: - Account Balance Editor Sheet

struct ReconciliationAccountEditor: View {
    let initial: BalanceDraft?
    let onSave: (String, Int, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var opening: Int
    @State private var closing: Int
    @State private var interest: Int

    init(initial: BalanceDraft?, onSave: @escaping (String, Int, Int, Int) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _name = State(initialValue: initial?.accountName ?? "")
        _opening = State(initialValue: initial?.opening ?? 0)
        _closing = State(initialValue: initial?.closing ?? 0)
        _interest = State(initialValue: initial?.interest ?? 0)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                TextField("계좌명", text: $name)
            }
            Section {
                reconciliationMoneyField("월초 잔액", value: $opening)
                reconciliationMoneyField("월말 잔액", value: $closing)
                reconciliationMoneyField("이자", value: $interest)
            }
        }
        .navigationTitle(initial == nil ? "계좌 추가" : "계좌 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    onSave(trimmedName, opening, closing, interest)
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
    }
}

// MARK: - Cash Adjustment Editor Sheet

struct ReconciliationAdjustmentEditor: View {
    let initial: AdjustmentDraft?
    let onSave: (String, CashAdjustmentDirection, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var direction: CashAdjustmentDirection
    @State private var amount: Int

    init(
        initial: AdjustmentDraft?,
        onSave: @escaping (String, CashAdjustmentDirection, Int) -> Void
    ) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _direction = State(initialValue: initial?.direction ?? .deposit)
        _amount = State(initialValue: initial?.amount ?? 0)
    }

    var body: some View {
        List {
            Section {
                TextField("항목", text: $title)
                Picker("방향", selection: $direction) {
                    ForEach(CashAdjustmentDirection.allCases, id: \.self) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                reconciliationMoneyField("금액", value: $amount)
            }
        }
        .navigationTitle(initial == nil ? "자금변동 추가" : "자금변동 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), direction, amount)
                    dismiss()
                }
                .disabled(amount <= 0)
            }
        }
    }
}

// MARK: - Shared Helpers

private func reconciliationMoneyField(_ title: String, value: Binding<Int>) -> some View {
    HStack {
        Text(title)
        Spacer()
        // Formatted amount TextField with comma grouping.
        TextField("0", value: reconciliationAmountValue(value), format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150)
        Text("원")
            .foregroundStyle(.secondary)
    }
}

/// Wraps 0 as nil for clean placeholder display.
private func reconciliationAmountValue(_ value: Binding<Int>) -> Binding<Int?> {
    Binding(
        get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
        set: { value.wrappedValue = $0 ?? 0 }
    )
}
