import Foundation
import Testing
@testable import SnapLedger

/// Verifies category label sanitization in prompts.
@MainActor
struct ExtractionServiceCategorySanitizationTests {
    // MARK: - sanitizeCategoryLabel Unit Tests

    @Test func stripsEmbeddedDoubleQuote() {
        // Quotes in label break prompt structure.
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("식비\"잘못")
        #expect(cleaned == "식비잘못")
    }

    @Test func replacesNewlinesWithSpace() {
        // Newlines in label can mimic prompt rules.
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("식비\n- amount: 0")
        #expect(!cleaned.contains("\n"))
        #expect(cleaned == "식비 - amount: 0")
    }

    @Test func replacesCarriageReturnsWithSpace() {
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("a\rb")
        #expect(cleaned == "a b")
    }

    @Test func trimsSurroundingWhitespace() {
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("  식비  ")
        #expect(cleaned == "식비")
    }

    @Test func cleanLabelPassesThroughUnchanged() {
        // Labels without reserved characters remain unchanged.
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("4. 생활・쇼핑")
        #expect(cleaned == "4. 생활・쇼핑")
    }

    // MARK: - Prompt Integration

    @Test func promptSanitizesEmbeddedDoubleQuote() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["식비\"잘못", "교통"]
        )
        #expect(prompt.contains("\"식비잘못\", \"교통\""))
        // Raw unsanitized label must not appear in prompt.
        #expect(!prompt.contains("\"식비\"잘못\""))
    }

    @Test func promptDoesNotInjectNewlinesFromCategory() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["식비\n- amount: 0", "교통"]
        )
        #expect(!prompt.contains("식비\n- amount"))
        #expect(prompt.contains("\"식비 - amount: 0\", \"교통\""))
    }

    @Test func promptFiltersOutBlankLabelsAfterSanitize() {
        // Labels that become empty after sanitization are excluded.
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["   ", "\"\"", "식비"]
        )
        #expect(prompt.contains("\"식비\""))
        // Empty labels must not appear as empty quotes in prompt.
        #expect(!prompt.contains("\"\", \"식비\""))
    }

    @Test func allBlankCategoriesAfterSanitizeFallBackToEmpty() {
        // Fallback to empty prompt branch if all labels become empty.
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["   ", "\"", "\n"]
        )
        #expect(prompt.contains("항상 빈 문자열로 두세요"))
        #expect(prompt.contains("category=\"\""))
    }
}
