import Foundation

extension FoundationModelsExtractionService {
    /// Whether every transaction of a non-empty answer copies the prompt's placeholder merchant.
    static func isExampleLeakOnly(_ extraction: PaymentExtraction) -> Bool {
        !extraction.transactions.isEmpty && extraction.transactions.allSatisfy(looksLikeExampleLeak)
    }

    /// Asks once more when the answer only echoes the placeholder; the second answer stands either way.
    static func retryingOnExampleLeak(
        _ attempt: () async throws -> PaymentExtraction
    ) async throws -> PaymentExtraction {
        let first = try await attempt()
        guard isExampleLeakOnly(first) else { return first }
        return try await attempt()
    }
}
