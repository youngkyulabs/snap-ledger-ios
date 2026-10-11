import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct ExtractionServiceSourceClampTests {
    private typealias Service = FoundationModelsExtractionService

    @Test func limitLeavesRoomForPromptAndResponse() {
        let limit = Service.sourceCharacterLimit(contextSize: 4_096, promptTokens: 1_900)

        #expect(limit == 4_096 - 1_900 - Service.responseTokenReserve)
    }

    @Test func largerContextRaisesLimit() {
        let small = Service.sourceCharacterLimit(contextSize: 4_096, promptTokens: 1_900)
        let large = Service.sourceCharacterLimit(contextSize: 8_192, promptTokens: 1_900)

        #expect(large == small + 4_096)
    }

    @Test func oversizedPromptKeepsMinimumLimit() {
        let limit = Service.sourceCharacterLimit(contextSize: 4_096, promptTokens: 4_000)

        #expect(limit == Service.minimumSourceCharacterLimit)
    }

    @Test func shortTextIsUnchanged() {
        let text = "홈플러스 강남점\n2026-06-14\n합계 49,200원"

        #expect(Service.clampSourceText(text, limit: 100) == text)
    }

    @Test func textAtLimitIsUnchanged() {
        let text = String(repeating: "가", count: 100)

        #expect(Service.clampSourceText(text, limit: 100) == text)
    }

    @Test func longTextKeepsWholeHeadAndTailLines() {
        let header = "홈플러스 강남점\n2026-06-14 18:32"
        let footer = "합계 1,234,500원\n신한카드 일시불"
        let items = (1...300).map { "삼겹살 600g \($0),900" }.joined(separator: "\n")
        let text = "\(header)\n\(items)\n\(footer)"

        let clamped = Service.clampSourceText(text, limit: 200)
        let originalLines = Set(text.split(separator: "\n"))

        #expect(clamped.count <= 200)
        #expect(clamped.hasPrefix(header))
        #expect(clamped.hasSuffix(footer))
        #expect(clamped.split(separator: "\n").allSatisfy(originalLines.contains))
    }

    @Test func singleLineTextIsCutWithinLimit() {
        let text = String(repeating: "가", count: 300)

        #expect(Service.clampSourceText(text, limit: 200).count == 200)
    }

    @Test func clampedSourceDropsItems() {
        let result = Service.dropPartialItems(receipt(itemCount: 2), sourceClamped: true)

        #expect(result.transactions.first?.items.isEmpty == true)
        #expect(result.transactions.first?.amount == 49_200)
    }

    @Test func itemsAtCapAreDropped() {
        let extraction = receipt(itemCount: PaymentTransaction.maximumItems)

        let result = Service.dropPartialItems(extraction, sourceClamped: false)

        #expect(result.transactions.first?.items.isEmpty == true)
    }

    @Test func completeItemsAreKept() {
        let extraction = receipt(itemCount: 2)

        #expect(Service.dropPartialItems(extraction, sourceClamped: false) == extraction)
    }

    private func receipt(itemCount: Int) -> PaymentExtraction {
        PaymentExtraction(transactions: [
            PaymentTransaction(
                date: "2026-06-14", amount: 49_200, merchant: "홈플러스 강남점", category: "생활",
                items: (0..<itemCount).map { PaymentLineItem(name: "품목\($0)", amount: 1_000) }
            ),
        ])
    }
}
