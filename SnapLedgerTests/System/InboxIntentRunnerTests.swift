import Foundation
import SwiftData
import Testing
@testable import SnapLedger

/// Records how many extraction calls run at once.
actor OverlapProbe {
    private(set) var maxRunning = 0
    private var running = 0

    func enter() {
        running += 1
        maxRunning = max(maxRunning, running)
    }

    func leave() {
        running -= 1
    }
}

/// Returns one 900원 payment named after its text, holding each call open so overlapping calls would show.
private struct EchoExtractionService: ExtractionService {
    let probe: OverlapProbe
    let isAvailable = true

    func extract(from text: String) async throws -> PaymentExtraction {
        await probe.enter()
        try? await Task.sleep(for: .milliseconds(30))
        await probe.leave()
        return PaymentExtraction(transactions: [
            PaymentTransaction(date: "2026-11-25", amount: 900, merchant: text, category: "", items: []),
        ])
    }
}

/// Holds its first extraction on the gate until the test releases it.
private struct GatedExtractionService: ExtractionService {
    let gate: OCRGate
    let isAvailable = true

    func extract(from text: String) async throws -> PaymentExtraction {
        await gate.enter()
        return PaymentExtraction(transactions: [
            PaymentTransaction(date: "2026-11-25", amount: 900, merchant: "가게", category: "", items: []),
        ])
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct InboxIntentRunnerTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeInbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID()).d", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRunner(
        container: ModelContainer,
        inbox: URL,
        ocr: any OCRService = StubOCRService(error: OCRError.invalidImage),
        extraction: any ExtractionService,
        deadline: Duration = .seconds(10)
    ) -> InboxIntentRunner {
        InboxIntentRunner(
            container: container,
            processor: PendingProcessor(
                inboxURL: inbox,
                ocrService: ocr,
                extractionService: extraction,
                categoryLearner: CategoryLearner(),
                drainState: DrainState()
            ),
            deadline: deadline,
            pollInterval: .milliseconds(10)
        )
    }

    private func rows(in container: ModelContainer) throws -> [PendingImage] {
        try ModelContext(container).fetch(FetchDescriptor<PendingImage>())
    }

    /// Polls until the condition holds, for work the test does not own.
    private func waitUntil(_ condition: () throws -> Bool) async throws {
        for _ in 0..<500 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition never held")
    }

    @Test func runsArrivingTogetherExtractOneAtATimeAndReportTheirOwnPayment() async throws {
        let container = try makeContainer()
        let probe = OverlapProbe()
        let runner = makeRunner(container: container, inbox: try makeInbox(), extraction: EchoExtractionService(probe: probe))

        async let first = runner.run(writing: Data("가게A 승인".utf8), fileExtension: "txt")
        async let second = runner.run(writing: Data("가게B 승인".utf8), fileExtension: "txt")
        async let third = runner.run(writing: Data("가게C 승인".utf8), fileExtension: "txt")
        let outcomes = try await [first, second, third]

        #expect(outcomes == [.added("가게A 승인 900원"), .added("가게B 승인 900원"), .added("가게C 승인 900원")])
        #expect(await probe.maxRunning == 1)
    }

    @Test func drainAlreadyRunningElsewhereFinishesTheRunsFile() async throws {
        let container = try makeContainer()
        let inbox = try makeInbox()
        let gate = OCRGate()
        let runner = makeRunner(
            container: container,
            inbox: inbox,
            ocr: GatedOCRService(gate: gate, text: "5,000원 일시불"),
            extraction: EchoExtractionService(probe: OverlapProbe())
        )
        // The app's own drain holds an image in its own context.
        let appContext = ModelContext(container)
        try Data([0xFF, 0xD8]).write(to: inbox.appendingPathComponent("held.jpg"))
        appContext.insert(PendingImage(filename: "held.jpg"))
        try appContext.save()
        let appDrain = Task { await runner.processor.drain(in: appContext) }
        await gate.waitStarted()

        async let outcome = runner.run(writing: Data("가게B 승인".utf8), fileExtension: "txt")
        try await waitUntil { try rows(in: container).count == 2 }
        await gate.release()

        #expect(try await outcome == .added("가게B 승인 900원"))
        await appDrain.value
    }

    @Test func textWithNothingFoundIsSkippedWithoutLeavingARow() async throws {
        let container = try makeContainer()
        let inbox = try makeInbox()
        let runner = makeRunner(
            container: container,
            inbox: inbox,
            extraction: StubExtractionService(result: PaymentExtraction(transactions: []))
        )

        let outcome = try await runner.run(
            writing: Data("최대 10,000원 할인 쿠폰".utf8), fileExtension: "txt", discardsWhenNothingFound: true
        )

        #expect(outcome == .skipped)
        #expect(try rows(in: container).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
    }

    @Test func imageWithNothingFoundKeepsItsFailedRowForManualEntry() async throws {
        let container = try makeContainer()
        let runner = makeRunner(
            container: container,
            inbox: try makeInbox(),
            ocr: StubOCRService(text: "풍경 사진"),
            extraction: StubExtractionService(result: PaymentExtraction(transactions: []))
        )

        let outcome = try await runner.run(writing: Data([0xFF, 0xD8]), fileExtension: "jpg")

        #expect(outcome == .nothingFound)
        #expect(try rows(in: container).map(\.state) == [.failed])
    }

    @Test func runPastItsDeadlineReportsQueuedAndKeepsTheRow() async throws {
        let container = try makeContainer()
        let gate = OCRGate()
        let runner = makeRunner(
            container: container,
            inbox: try makeInbox(),
            extraction: GatedExtractionService(gate: gate),
            deadline: .milliseconds(100)
        )

        let outcome = try await runner.run(writing: Data("가게 승인".utf8), fileExtension: "txt")

        #expect(outcome == .queued)
        #expect(try rows(in: container).count == 1)
        await gate.release()
        try await waitUntil { try rows(in: container).first?.state == .done }
    }

    @Test func learnedCategoryAppliesToTheRunsEntry() async throws {
        let container = try makeContainer()
        try CategoryLearner().learn(merchant: "GS25", category: "카페", in: ModelContext(container))
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(date: "2026-11-25", amount: 3_000, merchant: "GS25", category: "기타", items: []),
        ])
        let runner = makeRunner(container: container, inbox: try makeInbox(), extraction: StubExtractionService(result: extraction))

        _ = try await runner.run(writing: Data("GS25 3,000원 승인".utf8), fileExtension: "txt")

        let entries = try ModelContext(container).fetch(FetchDescriptor<ParsedEntry>())
        #expect(entries.map(\.category) == ["카페"])
    }

    @Test func unavailableModelLeavesTheFileQueued() async throws {
        let container = try makeContainer()
        let runner = makeRunner(
            container: container,
            inbox: try makeInbox(),
            extraction: StubExtractionService(result: PaymentExtraction(transactions: []), isAvailable: false)
        )

        let outcome = try await runner.run(writing: Data("가게 승인".utf8), fileExtension: "txt")

        #expect(outcome == .queued)
        #expect(try rows(in: container).map(\.state) == [.queued])
    }
}
