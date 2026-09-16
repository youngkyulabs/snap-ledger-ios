import SwiftUI
import SwiftData

/// Category totals for a month, opened from the category share chart.
struct CategoryTotalsSheet: View {
    let month: Int

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    /// Pushed category drill-down.
    @State private var path: [String] = []

    private var stats: StatisticsAggregation.MonthlyStats? {
        StatisticsAggregation.aggregate(entries: entries)
            .first { ($0.id.year ?? 0) * 100 + ($0.id.month ?? 0) == month }
    }

    var body: some View {
        let stats = self.stats
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(stats?.slices ?? []) { slice in
                        Button {
                            path.append(slice.category)
                        } label: {
                            CategoryBreakdownRow(slice: slice)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("카테고리를 누르면 항목을 볼 수 있어요.")
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .navigationTitle("카테고리별 합계")
            .navigationSubtitle("\(ledgerMonthLabel(month)) 합계 \((stats?.total ?? 0).formatted(.number))원")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { category in
                CategoryEntriesView(detail: CategoryEntriesDetail(category: category, monthKey: month))
            }
        }
    }
}

private struct CategoryBreakdownRow: View {
    let slice: StatisticsAggregation.CategorySlice

    var body: some View {
        HStack {
            Text(slice.category)
                .font(.body)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(slice.total.formatted(.number))원")
                    .font(.body.monospacedDigit())
                    .contentTransition(.numericText())
                Text(slice.share.formatted(.percent.precision(.fractionLength(0...1))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .contentShape(.rect)
    }
}
