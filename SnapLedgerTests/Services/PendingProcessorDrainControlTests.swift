import Foundation
import SwiftData
import Testing
@testable import SnapLedger

/// Cancels the surrounding task on its first call, then behaves like a normal stub.
struct CancellingOCRService: OCRService {
    let text: String

    func recognize(imageURL: URL) async throws -> String {
        withUnsafeCurrentTask { $0?.cancel() }
        return text
    }
}

@MainActor
@Suite(.serialized)
struct PendingProcessorDrainControlTests {
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

    private let oneTransaction = PaymentExtraction(transactions: [
        PaymentTransaction(date: "2026-05-17", amount: 5000, merchant: "스타벅스", category: "카페", items: []),
    ])

    @Test func drainStopsAtNextItemWhenCancelled() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            ctx.insert(PendingImage(filename: try writeFakeImage(name, in: inbox)))
        }
        try ctx.save()
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: CancellingOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: oneTransaction),
            categoryLearner: CategoryLearner()
        )

        let task = Task { await processor.drain(in: ctx) }
        await task.value

        let states = try ctx.fetch(FetchDescriptor<PendingImage>()).map(\.state)
        #expect(states.filter { $0 == .done }.count == 1)
        #expect(states.filter { $0 == .queued }.count == 2)
    }
}
