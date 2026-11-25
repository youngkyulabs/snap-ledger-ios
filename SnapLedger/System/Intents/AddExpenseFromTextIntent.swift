import AppIntents
import Foundation
import SwiftData

struct AddExpenseFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "텍스트에서 지출 추가"
    static let description = IntentDescription(
        "결제 문자나 알림 내용에서 지출 항목을 추출해서 찰칵가계부 검토 목록에 추가해요. 결제 내용이 없는 글은 건너뛰어요."
    )

    @Parameter(title: "텍스트")
    var text: String

    @Dependency private var modelContainer: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let outcome: InboxIntentOutcome
        if let payload = IntentTextInput.payload(from: text) {
            outcome = try await InboxIntentRunner(container: modelContainer).run(
                writing: Data(payload.utf8),
                fileExtension: InboxPayload.textExtension,
                discardsWhenNothingFound: true
            )
        } else {
            outcome = .skipped
        }
        return .result(value: outcome.message, dialog: "\(outcome.message)")
    }
}

/// Decides what an intent's text becomes in the inbox (pure).
enum IntentTextInput {
    /// Same cap the share extension applies to shared text.
    static let maxLength = 2_000

    /// Trimmed and capped text, or nil when it shows no payment signal; unattended automations queue nothing for it.
    static func payload(from text: String) -> String? {
        let clipped = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        return CandidateHeuristics.hasPaymentSignal(clipped) ? clipped : nil
    }
}
