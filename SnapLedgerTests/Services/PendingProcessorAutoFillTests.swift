import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct PendingProcessorAutoFillTests {
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

    @Test func processAutoFillsEmptyMerchantAndSingleAmount() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("autofill.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        // Empty extraction fills single candidates
        let ocr = "스타벅스\n5,000원 일시불"
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(date: "2026-05-17", amount: 0, merchant: "", category: "", items: []),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: ocr),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "스타벅스")
        #expect(parsed.first?.amount == 5000)
    }

    @Test func processLeavesAmountZeroWhenMultipleAmountCandidates() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("ambiguous.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        // Ambiguous multiple amount candidates remain 0
        let ocr = "스타벅스\n5,000원 일시불\n10,000원"
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(date: "2026-05-17", amount: 0, merchant: "", category: "", items: []),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: ocr),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "스타벅스")
        #expect(parsed.first?.amount == 0)
    }
}
