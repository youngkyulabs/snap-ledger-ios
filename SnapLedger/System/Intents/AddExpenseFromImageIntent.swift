import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct AddExpenseFromImageIntent: AppIntent {
    static let title: LocalizedStringResource = "이미지에서 지출 추가"
    static let description = IntentDescription(
        "결제 알림 스크린샷이나 영수증 사진에서 지출 항목을 자동 추출해서 찰칵가계부 검토 목록에 추가해요."
    )

    @Parameter(title: "이미지", supportedContentTypes: [.image])
    var image: IntentFile

    @Dependency private var modelContainer: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let candidate = (image.filename as NSString).pathExtension.lowercased()
        let outcome = try await InboxIntentRunner(container: modelContainer).run(
            writing: image.data,
            fileExtension: candidate.isEmpty ? "img" : candidate
        )
        return .result(value: outcome.message, dialog: "\(outcome.message)")
    }
}
