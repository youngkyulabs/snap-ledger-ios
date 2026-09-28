import Foundation
import SwiftData
import Testing
@testable import SnapLedger

/// Counts calls shared by every copy of a stub.
actor CallCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

/// Cancels the surrounding task on its second call, so the first item finishes and the second is cut off after OCR.
struct CancelOnSecondCallOCRService: OCRService {
    let counter = CallCounter()
    let text: String

    func recognize(imageURL: URL) async throws -> String {
        if await counter.next() == 2 {
            unsafe withUnsafeCurrentTask { task in unsafe task?.cancel() }
        }
        return text
    }
}

/// Holds the first OCR call open until the test releases it; later calls pass straight through.
actor OCRGate {
    private var entered = false
    private var released = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var proceedWaiter: CheckedContinuation<Void, Never>?

    func enter() async {
        guard !entered else { return }
        entered = true
        startWaiter?.resume()
        startWaiter = nil
        if released { return }
        await withCheckedContinuation { proceedWaiter = $0 }
    }

    func waitStarted() async {
        if entered { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        released = true
        proceedWaiter?.resume()
        proceedWaiter = nil
    }
}

/// Throws CancellationError from extraction, optionally cancelling the surrounding task first.
struct CancellationErrorExtractionService: ExtractionService {
    let cancelsTask: Bool
    let isAvailable = true

    func extract(from text: String) async throws -> PaymentExtraction {
        if cancelsTask {
            unsafe withUnsafeCurrentTask { task in unsafe task?.cancel() }
        }
        throw CancellationError()
    }
}

/// Holds its first call on the gate.
struct GatedOCRService: OCRService {
    let gate: OCRGate
    let text: String

    func recognize(imageURL: URL) async throws -> String {
        await gate.enter()
        return text
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
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
            ocrService: CancelOnSecondCallOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: oneTransaction),
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )

        let task = Task { await processor.drain(in: ctx) }
        await task.value

        let states = try ctx.fetch(FetchDescriptor<PendingImage>()).map(\.state)
        #expect(states.filter { $0 == .done }.count == 1)
        #expect(states.filter { $0 == .queued }.count == 2)
    }

    @Test func drainRequestedWhileRunningRunsAgain() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        ctx.insert(PendingImage(filename: try writeFakeImage("first.jpg", in: inbox)))
        try ctx.save()
        let gate = OCRGate()
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: GatedOCRService(gate: gate, text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: oneTransaction),
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )

        let first = Task { await processor.drain(in: ctx) }
        await gate.waitStarted()
        // Arrives while the first drain is still running.
        ctx.insert(PendingImage(filename: try writeFakeImage("second.jpg", in: inbox)))
        try ctx.save()
        await processor.drain(in: ctx)
        await gate.release()
        await first.value

        let states = try ctx.fetch(FetchDescriptor<PendingImage>()).map(\.state)
        #expect(states.count == 2)
        #expect(states.allSatisfy { $0 == .done })
    }

    @Test func cancelledExtractionLeavesItemQueued() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let pending = PendingImage(filename: try writeFakeImage("cut.jpg", in: inbox))
        ctx.insert(pending)
        try ctx.save()
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: CancellationErrorExtractionService(cancelsTask: true),
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )

        // The stub cancels this inner task, not the test's own.
        await Task { await processor.process(pending, in: ctx) }.value

        #expect(pending.state == .queued)
        #expect(pending.failureMessage == nil)
        #expect(try ctx.fetch(FetchDescriptor<ParsedEntry>()).isEmpty)
    }

    @Test func cancellationErrorWithoutCancelledTaskMarksFailed() async throws {
        // Requeueing here would strand the item behind a drain that has already passed it.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let pending = PendingImage(filename: try writeFakeImage("stray.jpg", in: inbox))
        ctx.insert(pending)
        try ctx.save()
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: CancellationErrorExtractionService(cancelsTask: false),
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )

        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
    }

    @Test func requeueSkipsItemCurrentlyProcessing() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let pending = PendingImage(filename: try writeFakeImage("busy.jpg", in: inbox))
        ctx.insert(pending)
        try ctx.save()
        let gate = OCRGate()
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: GatedOCRService(gate: gate, text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: oneTransaction),
            categoryLearner: CategoryLearner(),
            drainState: DrainState()
        )

        let work = Task { await processor.process(pending, in: ctx) }
        await gate.waitStarted()
        // A foreground drain must not steal an item another caller is mid-way through.
        processor.requeueStaleProcessing(in: ctx)
        #expect(pending.state == .processing)

        await gate.release()
        await work.value
        #expect(pending.state == .done)
        #expect(try ctx.fetch(FetchDescriptor<ParsedEntry>()).count == 1)
    }
}
