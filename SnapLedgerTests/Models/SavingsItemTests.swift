import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
struct SavingsItemTests {
    @Test func persistsAndFetches() throws {
        let container = try ModelContainer(
            for: SavingsItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(SavingsItem(monthKey: 202_606, title: "적금", amount: 500_000, sortOrder: 0))
        try context.save()

        let items = try context.fetch(FetchDescriptor<SavingsItem>())
        #expect(items.count == 1)
        #expect(items.first?.title == "적금")
        #expect(items.first?.amount == 500_000)
    }
}
