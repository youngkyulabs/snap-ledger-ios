import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct PendingProcessorRequeueTests {
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

    @Test func drainRequeuesAndProcessesStuckProcessing() async throws {
        // Requeues stale processing images to queued state.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("stuck.jpg", in: inbox)

        let pending = PendingImage(filename: filename, state: .processing)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1000,
                merchant: "Z", category: "", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        #expect(pending.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "Z")
    }

    @Test func drainRequeuesStuckProcessingWithMissingFileToFailed() async throws {
        // Missing file transitions to failed during OCR step.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        // File omitted to simulate missing inbox file

        let pending = PendingImage(filename: "gone.jpg", state: .processing)
        ctx.insert(pending)
        try ctx.save()

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [
                PaymentTransaction(date: "", amount: 0, merchant: "", category: "", items: []),
            ])),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        #expect(pending.state == .failed)
    }
}
