import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: PendingImage.self, ParsedEntry.self, SavedEntry.self,
        MerchantCategory.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

@MainActor
struct ModelsTests {
    @Test func pendingImageRoundTrip() throws {
        let ctx = try makeContext()
        let item = PendingImage(filename: "abc.jpg")
        ctx.insert(item)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.filename == "abc.jpg")
        #expect(fetched.first?.state == .queued)
        #expect(fetched.first?.failureMessage == nil)
    }

    @Test func pendingImageStateUpdates() throws {
        let ctx = try makeContext()
        let item = PendingImage(filename: "abc.jpg")
        ctx.insert(item)
        item.state = .processing
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PendingImage>())
        #expect(fetched.first?.state == .processing)
    }

    @Test func parsedEntryRoundTrip() throws {
        let ctx = try makeContext()
        let entry = ParsedEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 5000,
            merchant: "스타벅스",
            category: "카페",
            confidence: 0.92
        )
        ctx.insert(entry)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.merchant == "스타벅스")
        #expect(fetched.first?.amount == 5000)
        #expect(fetched.first?.confidence == 0.92)
        #expect(fetched.first?.status == .pending)
    }

    @Test func parsedEntryDefaultsOptionalsToNil() throws {
        let ctx = try makeContext()
        let entry = ParsedEntry(date: .now, amount: 1000, merchant: "GS25")
        ctx.insert(entry)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(fetched.first?.category == nil)
        #expect(fetched.first?.sourceImagePath == nil)
        #expect(fetched.first?.merchantCandidates.isEmpty == true)
        #expect(fetched.first?.amountCandidates.isEmpty == true)
        #expect(fetched.first?.failureReason == nil)
    }

    @Test func parsedEntryStoresCandidates() throws {
        let ctx = try makeContext()
        let entry = ParsedEntry(
            date: .now, amount: 5000, merchant: "투썸",
            merchantCandidates: ["투썸", "스타벅스"],
            amountCandidates: [5000, 10000]
        )
        ctx.insert(entry)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ParsedEntry>())
        #expect(fetched.first?.merchantCandidates == ["투썸", "스타벅스"])
        #expect(fetched.first?.amountCandidates == [5000, 10000])
    }

    @Test func savedEntryRoundTrip() throws {
        let ctx = try makeContext()
        let entry = SavedEntry(
            date: .now, amount: 3000, merchant: "GS25",
            category: "편의점", csvFile: "expenses-2026-05.csv"
        )
        ctx.insert(entry)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SavedEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.csvFile == "expenses-2026-05.csv")
        #expect(fetched.first?.category == "편의점")
    }

    @Test func merchantCategoryStoresAndFetches() throws {
        let ctx = try makeContext()
        ctx.insert(MerchantCategory(merchantNormalized: "starbucks", category: "카페"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantNormalized == "starbucks" }
        ))
        #expect(fetched.count == 1)
        #expect(fetched.first?.category == "카페")
    }

    @Test func appSettingsDefaults() throws {
        let ctx = try makeContext()
        let s = AppSettings()
        ctx.insert(s)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(fetched.first?.reminderHour == 21)
        #expect(fetched.first?.reminderMinute == 0)
        #expect(fetched.first?.csvFolderBookmark == nil)
        #expect(fetched.first?.categoryPresets.contains("식비") == true)
        #expect(fetched.first?.categoryPresets.contains("기타") == true)
    }
}
