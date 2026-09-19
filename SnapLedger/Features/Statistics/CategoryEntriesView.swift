import SwiftUI
import SwiftData

/// Context for category drill-down (month key and category).
struct CategoryEntriesDetail: Identifiable, Equatable {
    let category: String
    /// Month integer key (YYYYMM).
    let monthKey: Int

    var id: String { "\(monthKey)-\(category)" }
}

/// Entries for a single category in a given month.
struct CategoryEntriesView: View {
    let detail: CategoryEntriesDetail
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]

    private var filtered: [SavedEntry] {
        StatisticsAggregation.filteredEntries(entries, category: detail.category, monthKey: detail.monthKey)
    }

    private var days: [HistoryGrouping.DayGroup] {
        HistoryGrouping.group(entries: filtered).first?.days ?? []
    }

    private var total: Int {
        filtered.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Group {
            if days.isEmpty {
                ContentUnavailableView(
                    "항목 없음",
                    systemImage: "list.bullet.rectangle",
                    description: Text("이 달에는 이 카테고리 기록이 없어요.")
                )
            } else {
                List {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                CategoryEntryRow(entry: entry)
                            }
                        } header: {
                            Text(day.title).textCase(nil)
                        }
                    }
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
            }
        }
        .navigationTitle(detail.category)
        .navigationSubtitle("\(ledgerMonthLabel(detail.monthKey)) 합계 \(total.formatted(.number))원")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategoryEntryRow: View {
    let entry: SavedEntry

    private var hasNote: Bool {
        !(entry.note?.isEmpty ?? true)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.merchant).font(.body)
            Spacer()
            if hasNote {
                Image(systemName: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("메모 있음")
            }
            Text("\(entry.amount.formatted(.number))원")
                .font(.body.monospacedDigit())
        }
    }
}
