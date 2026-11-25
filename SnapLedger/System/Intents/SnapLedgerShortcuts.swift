import AppIntents

struct SnapLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseFromImageIntent(),
            phrases: [
                "\(.applicationName)에 지출 추가",
                "\(.applicationName)에서 영수증 추가",
                "Add expense to \(.applicationName)",
                "Add receipt to \(.applicationName)",
            ],
            shortTitle: "지출 추가",
            systemImageName: "doc.text.viewfinder"
        )
        AppShortcut(
            intent: AddExpenseFromTextIntent(),
            phrases: [
                "\(.applicationName)에 결제 문자 추가",
            ],
            shortTitle: "텍스트로 추가",
            systemImageName: "text.viewfinder"
        )
    }
}
