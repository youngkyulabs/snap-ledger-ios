import Foundation
import Testing
import SwiftData
@testable import SnapLedger

@MainActor
struct IncomeItemTests {
    @Test func persistsAndFetches() throws {
        let container = try ModelContainer(
            for: IncomeItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(IncomeItem(monthKey: 202_606, title: "월급", amount: 3_000_000, sortOrder: 0))
        try context.save()

        let items = try context.fetch(FetchDescriptor<IncomeItem>())
        #expect(items.count == 1)
        #expect(items.first?.title == "월급")
        #expect(items.first?.amount == 3_000_000)
    }
}
