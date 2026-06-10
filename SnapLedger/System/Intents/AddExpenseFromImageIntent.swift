import AppIntents
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "intent")

struct AddExpenseFromImageIntent: AppIntent {
    static let title: LocalizedStringResource = "이미지에서 지출 추가"
    static let description = IntentDescription(
        "결제 알림 스크린샷이나 영수증 사진에서 지출 항목을 자동 추출해서 찰칵가계부 검토 목록에 추가해요."
    )

    @Parameter(title: "이미지", supportedContentTypes: [.image])
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let inboxURL = AppGroup.inboxURL
        let ext: String = {
            let candidate = (image.filename as NSString).pathExtension.lowercased()
            return candidate.isEmpty ? "img" : candidate
        }()
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = inboxURL.appendingPathComponent(filename)
        try image.data.write(to: destination, options: .atomic)

        // 메인 앱과 같은 App Group 스토어를 열므로 스키마도 반드시 동일해야 한다.
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let pending = PendingImage(filename: filename)
        context.insert(pending)
        try context.save()

        guard FoundationModelsExtractionService.isAvailable else {
            return .result(value: "검토 목록에 추가했어요. 앱에서 처리할게요.")
        }

        let processor = PendingProcessor(
            inboxURL: inboxURL,
            ocrService: VisionKitOCRService(),
            extractionService: FoundationModelsExtractionService(
                customGuide: AppSettings.currentGuide(in: context),
                categories: AppSettings.currentCategories(in: context)
            ),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: context)

        let descriptor = FetchDescriptor<ParsedEntry>(
            predicate: #Predicate { $0.sourceImagePath == filename }
        )
        let entries: [ParsedEntry]
        do {
            entries = try context.fetch(descriptor)
        } catch {
            log.error("intent summary fetch failed: \(String(describing: error))")
            entries = []
        }
        let summary = entries
            .map { "\($0.merchant) \($0.amount.formatted(.number))원" }
            .joined(separator: ", ")
        return .result(value: summary.isEmpty ? "처리할 결제 내역을 찾지 못했어요." : summary)
    }
}
