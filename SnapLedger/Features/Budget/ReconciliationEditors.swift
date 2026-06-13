import SwiftUI

// MARK: - 항목 편집 시트 (수입·저축·카드 공용)

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

// MARK: - 계좌 편집 시트

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

// MARK: - 자금변동 편집 시트

struct ReconciliationAdjustmentEditor: View {
    let month: Int
    let initial: AdjustmentDraft?
    let onSave: (String, CashAdjustmentDirection, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var direction: CashAdjustmentDirection
    @State private var amount: Int

    init(
        month: Int,
        initial: AdjustmentDraft?,
        onSave: @escaping (String, CashAdjustmentDirection, Int) -> Void
    ) {
        self.month = month
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

// MARK: - 공용 헬퍼

private func reconciliationMoneyField(_ title: String, value: Binding<Int>) -> some View {
    HStack {
        Text(title)
        Spacer()
        TextField("0", text: reconciliationAmountBinding(value))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150)
        Text("원")
            .foregroundStyle(.secondary)
    }
}

private func reconciliationAmountBinding(_ value: Binding<Int>) -> Binding<String> {
    Binding(
        get: {
            value.wrappedValue == 0 ? "" : value.wrappedValue.formatted(.number)
        },
        set: { newValue in
            value.wrappedValue = Int(newValue.filter(\.isNumber)) ?? 0
        }
    )
}
