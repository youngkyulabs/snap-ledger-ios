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
        // 이전 실행이 처리 도중 중단(크래시·BGTask 타임아웃)돼 .processing 상태로 남은 항목은
        // 검토 탭에 "처리 중"으로 영구 표시된다. drain 이 이를 .queued 로 되돌려 재처리해야 한다.
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
        // .processing 으로 남았는데 원본 파일이 사라진 경우: 재처리 중 OCR 단계에서 실패해
        // .failed 로 전이되어야 한다 (영구 "처리 중"에 갇히지 않고 사용자가 정리 가능).
        let ctx = ModelContext(try makeContainer())
        let inbox = try makeInbox()
        // 파일을 만들지 않음 — 처리 중 사라진 상황

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
