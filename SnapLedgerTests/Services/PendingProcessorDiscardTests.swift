import Foundation
import SwiftData
import Testing
@testable import SnapLedger

/// Throws a non-cancellation error, as a failed model request would.
private struct FailingExtractionService: ExtractionService {
    struct Failure: Error {}
    let isAvailable = true

    func extract(from text: String) async throws -> PaymentExtraction {
        throw Failure()
    }
}

@MainActor
@Suite(.serialized)
struct PendingProcessorDiscardTests {
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

    private func writeText(_ text: String, named name: String, in folder: URL) throws -> String {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return name
    }

    private func makeProcessor(inbox: URL, extraction: any ExtractionService) -> PendingProcessor {
        PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: extraction,
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )
    }

    @Test func flaggedTextWithNothingFoundLeavesNoRowOrFile() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeText("최대 10,000원 할인 쿠폰이 도착했어요", named: "promo.txt", in: inbox)
        let pending = PendingImage(filename: filename, discardsWhenNothingFound: true)
        ctx.insert(pending)
        try ctx.save()

        let processor = makeProcessor(inbox: inbox, extraction: StubExtractionService(result: PaymentExtraction(transactions: [])))
        await processor.process(pending, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<PendingImage>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
    }

    @Test func flaggedTextWhoseExtractionThrowsStaysForRetry() async throws {
        // A thrown request may still be a real payment, so only an empty result is discarded.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeText("12,300원 일시불 스타벅스", named: "sms.txt", in: inbox)
        let pending = PendingImage(filename: filename, discardsWhenNothingFound: true)
        ctx.insert(pending)
        try ctx.save()

        await makeProcessor(inbox: inbox, extraction: FailingExtractionService()).process(pending, in: ctx)

        #expect(pending.state == .failed)
        #expect(PendingProcessor.isRetryable(failureMessage: pending.failureMessage))
        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
    }
}
