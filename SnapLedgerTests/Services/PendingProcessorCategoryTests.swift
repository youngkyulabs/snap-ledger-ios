import Foundation
import Testing
import SwiftData
@testable import SnapLedger

/// Verifies learned category resolution rules.
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

    /// Learned category in presets takes precedence.
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

    /// Off-preset learned categories fallback to extracted value.
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
