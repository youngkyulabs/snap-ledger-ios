import Foundation
import Testing
import SwiftData
@testable import SnapLedger

struct StubOCRService: OCRService {
    let text: String
    let error: (any Error)?

    init(text: String = "", error: (any Error)? = nil) {
        self.text = text
        self.error = error
    }

    func recognize(imageURL: URL) async throws -> String {
        if let error { throw error }
        return text
    }
}

@MainActor
@Suite(.serialized)
struct PendingProcessorTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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

    @Test func processPopulatesCandidatesFromOCRText() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("multi.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        // OCR이 여러 가맹점·금액 후보를 갖는 영수증·푸시 텍스트라고 가정
        let ocr = "스타벅스\n투썸플레이스\n5,000원 일시불\n10,000원\n부가세 909"
        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 5000,
                merchant: "스타벅스", category: "카페", items: []
            ),
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
        #expect(parsed.first?.merchantCandidates == ["스타벅스", "투썸플레이스"])
        #expect(parsed.first?.amountCandidates == [5000, 10000])
    }

    @Test func processAdvancesStateForCardNotification() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("card.jpg", in: inbox)

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
            ocrService: StubOCRService(text: "신한카드 승인"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "스타벅스")
        #expect(parsed.first?.amount == 5000)
        #expect(parsed.first?.category == "카페")
    }

    @Test func processCreatesOneEntryPerReceiptItem() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("receipt.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 8000,
                merchant: "스타벅스", category: "카페",
                items: [
                    PaymentLineItem(name: "아메리카노", amount: 5000),
                    PaymentLineItem(name: "샌드위치", amount: 3000),
                ]
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
        #expect(parsed.count == 2)
        let merchants = parsed.map(\.merchant).sorted()
        #expect(merchants == ["스타벅스 - 샌드위치", "스타벅스 - 아메리카노"])
        let amounts = parsed.map(\.amount).sorted()
        #expect(amounts == [3000, 5000])
    }

    @Test func learnedCategoryOverridesExtractionCategory() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("gs.jpg", in: inbox)

        // Pre-existing learned mapping
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
        #expect(parsed.first?.category == "편의점")
    }

    @Test func ocrFailureMarksPendingFailed() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("bad.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
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
        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
        #expect(pending.failureMessage != nil)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.isEmpty)
    }

    @Test func drainReconcilesAndProcessesDroppedFiles() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeFakeImage("shared.jpg", in: inbox)
        // No PendingImage row inserted — simulates extension-dropped file

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1000,
                merchant: "Y", category: "", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.count == 1)
        #expect(pending.first?.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "Y")
    }

    @Test func processDeletesInboxFileOnSuccess() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("ok.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1000,
                merchant: "X", category: "", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .done)
        let imagePath = inbox.appendingPathComponent(filename).path
        #expect(!FileManager.default.fileExists(atPath: imagePath))
    }

    @Test func processKeepsInboxFileOnFailure() async throws {
        // 실패한 이미지는 사용자가 검토 탭 배너에서 정리할 때까지 보관한다.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("bad.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
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
        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
        let imagePath = inbox.appendingPathComponent(filename).path
        #expect(FileManager.default.fileExists(atPath: imagePath))
    }

    @Test func drainSkipsWhenExtractionServiceUnavailable() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("queued.jpg", in: inbox)

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(
                result: PaymentExtraction(transactions: [
                    PaymentTransaction(date: "", amount: 0, merchant: "", category: "", items: []),
                ]),
                isAvailable: false
            ),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.isEmpty)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.isEmpty)
        let imagePath = inbox.appendingPathComponent(filename).path
        #expect(FileManager.default.fileExists(atPath: imagePath))
    }

    @Test func drainProcessesAllQueuedItems() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeFakeImage("a.jpg", in: inbox)
        _ = try writeFakeImage("b.jpg", in: inbox)

        ctx.insert(PendingImage(filename: "a.jpg"))
        ctx.insert(PendingImage(filename: "b.jpg"))
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 1000,
                merchant: "X", category: "", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.drain(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.allSatisfy { $0.state == .done })
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 2)
    }

    @Test func processCreatesOneEntryPerTransaction() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("multi.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-05-17", amount: 3300, merchant: "Apple", category: "쇼핑", items: []
            ),
            PaymentTransaction(
                date: "2026-05-17", amount: 25020, merchant: "쿠팡", category: "쇼핑", items: []
            ),
            PaymentTransaction(
                date: "2026-05-16", amount: 10700, merchant: "투썸플레이스", category: "카페", items: []
            ),
        ])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .done)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 3)
        let merchants = Set(parsed.map(\.merchant))
        #expect(merchants == ["Apple", "쿠팡", "투썸플레이스"])
        let amounts = parsed.map(\.amount).sorted()
        #expect(amounts == [3300, 10700, 25020])
    }

    @Test func processEmptyTransactionsMarksPendingFailed() async throws {
        // OCR 텍스트에 결제 신호는 있지만 LLM 추출 결과가 비어 있는 경우
        // ParsedEntry 를 만들지 않고 PendingImage 자체를 failed 로 표시한다.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("empty.jpg", in: inbox)

        let pending = PendingImage(filename: filename)
        ctx.insert(pending)
        try ctx.save()

        let extraction = PaymentExtraction(transactions: [])
        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(text: "5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        #expect(pending.state == .failed)
        #expect(pending.failureMessage == PendingProcessor.noPaymentSignalReason)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.isEmpty)
    }
}

@MainActor
@Suite(.serialized)
struct PendingProcessorReconcileInboxTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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

    @Test func reconcileInboxCreatesPendingForNewFiles() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeFakeImage("a.jpg", in: inbox)
        _ = try writeFakeImage("b.png", in: inbox)

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [
                PaymentTransaction(date: "", amount: 0, merchant: "", category: "", items: []),
            ])),
            categoryLearner: CategoryLearner()
        )
        processor.reconcileInbox(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        let names = Set(pending.map(\.filename))
        #expect(names == ["a.jpg", "b.png"])
        #expect(pending.allSatisfy { $0.state == .queued })
    }

    @Test func reconcileInboxSkipsAlreadyTrackedFiles() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeFakeImage("a.jpg", in: inbox)
        _ = try writeFakeImage("b.jpg", in: inbox)

        ctx.insert(PendingImage(filename: "a.jpg"))
        try ctx.save()

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [
                PaymentTransaction(date: "", amount: 0, merchant: "", category: "", items: []),
            ])),
            categoryLearner: CategoryLearner()
        )
        processor.reconcileInbox(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.count == 2)
        #expect(Set(pending.map(\.filename)) == ["a.jpg", "b.jpg"])
    }

    @Test func reconcileInboxIgnoresHiddenFiles() async throws {
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        _ = try writeFakeImage("a.jpg", in: inbox)
        _ = try writeFakeImage(".DS_Store", in: inbox)

        let processor = PendingProcessor(
            inboxURL: inbox,
            ocrService: StubOCRService(),
            extractionService: StubExtractionService(result: PaymentExtraction(transactions: [
                PaymentTransaction(date: "", amount: 0, merchant: "", category: "", items: []),
            ])),
            categoryLearner: CategoryLearner()
        )
        processor.reconcileInbox(in: ctx)

        let pending = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(pending.map(\.filename) == ["a.jpg"])
    }
}

@MainActor
@Suite(.serialized)
struct PendingProcessorPaymentSignalGateTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
            MerchantCategory.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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

    @Test func processSkipsExtractionWhenOCRTextHasNoPaymentSignal() async throws {
        // 풍경 사진의 OCR 결과처럼 결제 신호가 없는 텍스트에서는 LLM이 환각으로
        // 가짜 거래를 만들어내더라도 게이트가 잘라내 빈 placeholder만 남아야 한다.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("landscape.jpg", in: inbox)

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
            ocrService: StubOCRService(text: "바다와 노을 풍경 사진"),
            extractionService: StubExtractionService(result: hallucinated),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        // 결제 신호가 없는 텍스트는 처음부터 LLM 호출도 안 하고, ParsedEntry 도
        // 만들지 않는다. PendingImage 만 failed 로 표시되어 검토 탭 배너에 카운트로
        // 노출된다 — 환각 가맹점이 검토 항목에 새지 않음을 보증.
        #expect(pending.state == .failed)
        #expect(pending.failureMessage == PendingProcessor.noPaymentSignalReason)
        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.isEmpty)
    }

    @Test func processCallsExtractionWhenOCRTextHasPaymentSignal() async throws {
        // OCR에 결제 신호가 보이면 게이트 통과 — 정상 추출 흐름.
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        let filename = try writeFakeImage("receipt.jpg", in: inbox)

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
            ocrService: StubOCRService(text: "스타벅스 5,000원 일시불"),
            extractionService: StubExtractionService(result: extraction),
            categoryLearner: CategoryLearner()
        )
        await processor.process(pending, in: ctx)

        let parsed = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(parsed.count == 1)
        #expect(parsed.first?.merchant == "스타벅스")
        #expect(parsed.first?.amount == 5000)
    }
}
