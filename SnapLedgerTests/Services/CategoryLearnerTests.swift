import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
struct CategoryLearnerTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: MerchantCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func normalizationCases() {
        #expect(CategoryLearner.normalize("STARBUCKS") == "starbucks")
        #expect(CategoryLearner.normalize("Starbucks.") == "starbucks")
        #expect(CategoryLearner.normalize("Star Bucks") == "starbucks")
        #expect(CategoryLearner.normalize("스타 벅스") == "스타벅스")
        #expect(CategoryLearner.normalize("(주)스타벅스") == "주스타벅스")
        #expect(CategoryLearner.normalize("CU 강남점") == "cu강남점")
    }

    @Test func unknownMerchantReturnsNil() throws {
        let ctx = try makeContext()
        let learner = CategoryLearner()
        #expect(try learner.category(for: "스타벅스", in: ctx) == nil)
    }

    @Test func roundTripLearnAndRecall() throws {
        let ctx = try makeContext()
        let learner = CategoryLearner()
        try learner.learn(merchant: "스타벅스", category: "카페", in: ctx)
        #expect(try learner.category(for: "스타벅스", in: ctx) == "카페")
    }

    @Test func recallsAcrossVariants() throws {
        let ctx = try makeContext()
        let learner = CategoryLearner()
        try learner.learn(merchant: "STARBUCKS", category: "카페", in: ctx)
        #expect(try learner.category(for: "Starbucks.", in: ctx) == "카페")
        #expect(try learner.category(for: "star bucks", in: ctx) == "카페")
        #expect(try learner.category(for: "스타벅스", in: ctx) == nil)  // different language, different key
    }

    @Test func updatingChangesLastCategoryWithoutDuplicating() throws {
        let ctx = try makeContext()
        let learner = CategoryLearner()
        try learner.learn(merchant: "GS25", category: "편의점", in: ctx)
        try learner.learn(merchant: "GS25", category: "식비", in: ctx)
        #expect(try learner.category(for: "GS25", in: ctx) == "식비")
        let all = try ctx.fetch(FetchDescriptor<MerchantCategory>())
        #expect(all.count == 1)
    }

    @Test func categoryReturnsLatestAmongDuplicates() throws {
        let context = try makeContext()
        let normalized = CategoryLearner.normalize("스타벅스")
        context.insert(MerchantCategory(merchantNormalized: normalized, category: "카페",
                                        updatedAt: Date(timeIntervalSince1970: 100)))
        context.insert(MerchantCategory(merchantNormalized: normalized, category: "간식",
                                        updatedAt: Date(timeIntervalSince1970: 200)))
        try context.save()

        let result = try CategoryLearner().category(for: "스타벅스", in: context)
        #expect(result == "간식")
    }

    @Test func learnMergesDuplicatesIntoOne() throws {
        let context = try makeContext()
        let normalized = CategoryLearner.normalize("스타벅스")
        context.insert(MerchantCategory(merchantNormalized: normalized, category: "카페",
                                        updatedAt: Date(timeIntervalSince1970: 100)))
        context.insert(MerchantCategory(merchantNormalized: normalized, category: "간식",
                                        updatedAt: Date(timeIntervalSince1970: 200)))
        try context.save()

        try CategoryLearner().learn(merchant: "스타벅스", category: "교통", in: context)

        let all = try context.fetch(FetchDescriptor<MerchantCategory>())
        #expect(all.count == 1)
        #expect(all.first?.category == "교통")
    }

    /// 인텐트(AddExpenseFromImageIntent)는 localModels-only 컨테이너를 연다 —
    /// Phase 3에서 MerchantCategory가 cloudModels로 옮겨가 그 스키마에는 없다.
    /// 스키마에 엔티티가 없는 컨텍스트에서도 크래시 없이 nil/무동작이어야 한다.
    private func makeLocalOnlyContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.localModels),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func categoryReturnsNilWhenMerchantEntityAbsent() throws {
        let context = try makeLocalOnlyContext()
        #expect(try CategoryLearner().category(for: "스타벅스", in: context) == nil)
    }

    @Test func learnIsNoOpWhenMerchantEntityAbsent() throws {
        let context = try makeLocalOnlyContext()
        try CategoryLearner().learn(merchant: "스타벅스", category: "카페", in: context)
        // 크래시 없이 여기까지 도달하면 성공.
    }
}
