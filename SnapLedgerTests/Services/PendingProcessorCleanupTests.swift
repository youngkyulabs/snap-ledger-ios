import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
@Suite(.serialized)
struct PendingProcessorCleanupTests {
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

    private func makeProcessor(inbox: URL) -> PendingProcessor {
        PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [])),
            categoryLearner: CategoryLearner()
        )
    }

    @Test func keepsImageWhilePendingEntryReferencesIt() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("keep.jpg", in: inbox)
        ctx.insert(PendingImage(filename: filename, state: .done))
        ctx.insert(ParsedEntry(date: .now, amount: 1000, merchant: "X", sourceImagePath: filename))
        try ctx.save()

        makeProcessor(inbox: inbox).cleanupResolvedImages(in: ctx)

        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
        #expect(try ctx.fetch(FetchDescriptor<PendingImage>()).count == 1)
    }

    @Test func removesImageWhenAllReferencingEntriesResolved() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("gone.jpg", in: inbox)
        ctx.insert(PendingImage(filename: filename, state: .done))
        // Dismissed entries no longer hold image references.
        ctx.insert(ParsedEntry(
            date: .now, amount: 1000, merchant: "X",
            sourceImagePath: filename, status: .dismissed
        ))
        try ctx.save()

        makeProcessor(inbox: inbox).cleanupResolvedImages(in: ctx)

        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
        #expect(try ctx.fetch(FetchDescriptor<PendingImage>()).isEmpty)
    }

    @Test func multiEntryImageKeptUntilLastResolved() async throws {
        // Retain image if at least one split entry is pending.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("receipt.jpg", in: inbox)
        ctx.insert(PendingImage(filename: filename, state: .done))
        ctx.insert(ParsedEntry(
            date: .now, amount: 1000, merchant: "A",
            sourceImagePath: filename, status: .dismissed
        ))
        ctx.insert(ParsedEntry(date: .now, amount: 2000, merchant: "B", sourceImagePath: filename))
        try ctx.save()

        makeProcessor(inbox: inbox).cleanupResolvedImages(in: ctx)

        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
    }

    @Test func leavesFailedImagesUntouched() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("failed.jpg", in: inbox)
        ctx.insert(PendingImage(filename: filename, state: .failed, failureMessage: "err"))
        try ctx.save()

        makeProcessor(inbox: inbox).cleanupResolvedImages(in: ctx)

        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent(filename).path))
        #expect(try ctx.fetch(FetchDescriptor<PendingImage>()).count == 1)
    }
}
