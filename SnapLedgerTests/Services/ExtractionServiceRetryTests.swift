import Foundation
import Testing
@testable import SnapLedger

/// Verifies the single retry when the model answers only with the prompt's placeholder merchant.
@MainActor
struct ExtractionServiceRetryTests {
    private let leak = PaymentExtraction(transactions: [
        PaymentTransaction(date: "", amount: 0, merchant: "예시상호", category: "", items: []),
    ])
    private let real = PaymentExtraction(transactions: [
        PaymentTransaction(date: "2026-10-10", amount: 9000, merchant: "찌개애감동", category: "", items: []),
    ])

    /// Hands out the queued answers one per call and counts the calls.
    private final class Attempts {
        private var answers: [PaymentExtraction]
        private(set) var calls = 0

        init(_ answers: [PaymentExtraction]) {
            self.answers = answers
        }

        func next() throws -> PaymentExtraction {
            calls += 1
            guard !answers.isEmpty else { throw URLError(.unknown) }
            return answers.removeFirst()
        }
    }

    @Test func leakOnlyRequiresEveryTransactionToLeak() {
        let mixed = PaymentExtraction(transactions: leak.transactions + real.transactions)
        #expect(FoundationModelsExtractionService.isExampleLeakOnly(leak))
        #expect(!FoundationModelsExtractionService.isExampleLeakOnly(mixed))
        #expect(!FoundationModelsExtractionService.isExampleLeakOnly(PaymentExtraction(transactions: [])))
    }

    @Test func retriesOnceAfterALeak() async throws {
        let attempts = Attempts([leak, real])
        let out = try await FoundationModelsExtractionService.retryingOnExampleLeak { try attempts.next() }
        #expect(out == real)
        #expect(attempts.calls == 2)
    }

    @Test func doesNotRetryARealAnswer() async throws {
        let attempts = Attempts([real, leak])
        let out = try await FoundationModelsExtractionService.retryingOnExampleLeak { try attempts.next() }
        #expect(out == real)
        #expect(attempts.calls == 1)
    }

    @Test func stopsAfterTwoLeaks() async throws {
        let attempts = Attempts([leak, leak, real])
        let out = try await FoundationModelsExtractionService.retryingOnExampleLeak { try attempts.next() }
        #expect(out == leak)
        #expect(attempts.calls == 2)
    }

    @Test func rethrowsAttemptError() async {
        let attempts = Attempts([])
        await #expect(throws: URLError.self) {
            _ = try await FoundationModelsExtractionService.retryingOnExampleLeak { try attempts.next() }
        }
        #expect(attempts.calls == 1)
    }
}
