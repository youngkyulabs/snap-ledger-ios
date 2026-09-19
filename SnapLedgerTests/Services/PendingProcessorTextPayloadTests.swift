import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct PendingProcessorTextPayloadTests {
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

    private func writeSharedText(_ text: String, named name: String, in folder: URL) throws -> String {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return name
    }

    @Test func textPayloadExtractsWithoutOCR() async throws {
        // Shared text is fed to extraction directly; OCR must not run.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeSharedText(
            "[Web발신]\n신한카드(1234) 승인\n5,000원 일시불\n스타벅스 강남점",
            named: "sms.txt", in: inbox
        )

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000,
                merchant: "스타벅스 강남점", category: "카페", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            // OCR would throw if the text branch fell through to it.
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "스타벅스 강남점")
        #expect(parsed.first?.amount == 5000)
    }

    @Test func textPayloadPopulatesCandidatesFromSharedText() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeSharedText(
            "스타벅스\n투썸플레이스\n5,000원 일시불\n10,000원",
            named: "candidates.txt", in: inbox
        )

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000,
                merchant: "스타벅스", category: "카페", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.first?.merchantCandidates == ["스타벅스", "투썸플레이스"])
        #expect(parsed.first?.amountCandidates == [5000, 10000])
    }

    @Test func textWithoutPaymentSignalFailsWithTextReason() async throws {
        // Ordinary chat text must not reach the model, and gets its own copy.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeSharedText(
            "오늘 저녁에 볼까?", named: "chat.txt", in: inbox
        )

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let hallucinated = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 99999,
                merchant: "환각가맹점", category: "쇼핑", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: StubExtractionService(result: hallucinated),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
        #expect(pending.failureMessage == PendingProcessor.noPaymentSignalTextReason)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.isEmpty)
    }

    @Test func unreadableTextFileMarksPendingFailed() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()

        let pending = PendingImage(filename: "missing.txt")
        ctx.insert(pending)
        try ctx.save()

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [])),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
        #expect(pending.failureMessage != nil)
        #expect(PendingProcessor.isRetryable(failureMessage: pending.failureMessage))
    }

    @Test func drainReconcilesSharedTextFiles() async throws {
        // Extension drops a .txt with no PendingImage row.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeSharedText("신한카드 승인 5,000원", named: "dropped.txt", in: inbox)

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000,
                merchant: "스타벅스", category: "카페", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(error: OCRError.invalidImage),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.count == 1)
        #expect(pending.first?.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
    }

    @Test func textNoPaymentSignalFailureIsNotRetryable() {
        #expect(
            PendingProcessor.isRetryable(
                failureMessage: PendingProcessor.noPaymentSignalTextReason
            ) == false
        )
    }
}
