import SwiftUI
import SwiftData

/// 통계·예산 탭에서 카테고리를 탭했을 때 보여줄 대상 (그 달 + 카테고리).
struct CategoryEntriesDetail: Identifiable, Equatable {
    let category: String
    /// YYYYMM 정수 키 (`CategoryBudgetStore.monthKey`와 동일 규칙).
    let monthKey: Int

    var id: String { "\(monthKey)-\(category)" }
}

/// 한 달·한 카테고리의 항목 리스트 시트. 통계 탭 '카테고리별 합계'와
/// 예산 탭 카테고리 행에서 공용으로 쓴다.
struct CategoryEntriesSheet: View {
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
        NavigationStack {
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
            .navigationSubtitle("\(monthTitle) 합계 \(total.formatted(.number))원")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var monthTitle: String {
        var comps = DateComponents()
        comps.year = detail.monthKey / 100
        comps.month = detail.monthKey % 100
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
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

#Preview {
    CategoryEntriesSheet(detail: CategoryEntriesDetail(category: "식비", monthKey: 202606))
        .modelContainer(for: SavedEntry.self, inMemory: true)
}
