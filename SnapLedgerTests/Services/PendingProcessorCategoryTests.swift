import Foundation
import Testing
import SwiftData
@testable import SnapLedger

/// 검토 항목 생성 시 가맹점→카테고리 학습값의 적용 규칙.
/// 학습값이 현재 프리셋 안일 때만 추출값을 이기고, 프리셋 밖(사용자가 지운 옛
/// 카테고리)이면 되살리지 않고 추출값으로 폴백한다.
@MainActor
@Suite(.serialized)
struct PendingProcessorCategoryTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeInbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID()).d", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFakeImage(_ name: String, in folder: URL) throws -> String {
        let url = folder.appendingPathComponent(name)
        try Data([0xFF, 0xD8]).write(to: url)
        return name
    }

    /// 학습값이 현재 프리셋 안(유효)이면 추출 카테고리를 이긴다.
    @Test func learnedCategoryOverridesExtractionCategory() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("gs.jpg", in: inbox)

        try CategoryLearner().learn(merchant: "GS25", category: "카페", in: ctx)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 3000,
                merchant: "GS25", category: "기타", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.first?.category == "카페")
    }

    /// 프리셋에서 지운 옛 학습값은 검토 자동채움에서 되살리지 않고 추출값으로 폴백한다.
    /// "편의점"은 기본 프리셋에 없으므로(off-list) 드롭되고 추출 카테고리 "기타"가 남는다.
    @Test func offPresetLearnedCategoryFallsBackToExtraction() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("gs2.jpg", in: inbox)

        try CategoryLearner().learn(merchant: "GS25", category: "편의점", in: ctx)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 3000,
                merchant: "GS25", category: "기타", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.first?.category == "기타")
    }
}
