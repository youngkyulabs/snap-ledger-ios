import Foundation
import Testing
@testable import SnapLedger

/// `FoundationModelsExtractionService.sanitizeCategoryLabel` 와 prompt에서의
/// 사용을 검증한다. 사용자가 카테고리 라벨에 따옴표·줄바꿈을 넣어도 prompt의
/// `"label1", "label2"` 구조가 깨지지 않아야 한다.
@MainActor
struct ExtractionServiceCategorySanitizationTests {
    // MARK: - sanitizeCategoryLabel 단위

    @Test func stripsEmbeddedDoubleQuote() {
        // 라벨 안의 `"`는 prompt의 `"label1", "label2"` 구조를 깨뜨려
        // 모델이 라벨 경계를 헷갈리게 한다.
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("식비\"잘못")
        #expect(cleaned == "식비잘못")
    }

    @Test func replacesNewlinesWithSpace() {
        // 라벨에 줄바꿈이 들어가면 prompt 본문의 다음 줄을 흉내내
        // 모델이 새 규칙으로 오인할 수 있다.
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
        // 위험 문자가 없는 라벨은 그대로.
        let cleaned = FoundationModelsExtractionService.sanitizeCategoryLabel("4. 생활・쇼핑")
        #expect(cleaned == "4. 생활・쇼핑")
    }

    // MARK: - prompt 통합

    @Test func promptSanitizesEmbeddedDoubleQuote() {
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["식비\"잘못", "교통"]
        )
        #expect(prompt.contains("\"식비잘못\", \"교통\""))
        // sanitize 전 형태(`"식비"잘못"`)는 prompt에 노출되면 안 됨.
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
        // sanitize 후 빈 문자열이 되는 라벨(공백만/따옴표만)은 list에서 제외.
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["   ", "\"\"", "식비"]
        )
        #expect(prompt.contains("\"식비\""))
        // 빈 라벨이 그대로 들어가서 `""` 두 개가 prompt에 나타나면 안 됨.
        #expect(!prompt.contains("\"\", \"식비\""))
    }

    @Test func allBlankCategoriesAfterSanitizeFallBackToEmpty() {
        // 입력 자체는 비어있지 않지만 sanitize 후 모두 빈 문자열이면
        // 빈 카테고리 목록과 같은 경로로 fallback 해야 한다.
        let prompt = FoundationModelsExtractionService.instructions(
            today: .now,
            customGuide: "",
            categories: ["   ", "\"", "\n"]
        )
        #expect(prompt.contains("항상 빈 문자열로 두세요"))
        #expect(prompt.contains("category=\"\""))
    }
}
