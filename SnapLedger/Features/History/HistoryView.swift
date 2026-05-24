import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var monthsBack: Int = 0

    private var allMonths: [HistoryGrouping.MonthGroup] {
        HistoryGrouping.group(entries: entries)
    }

    private var displayedMonths: [HistoryGrouping.MonthGroup] {
        Array(allMonths.prefix(monthsBack + 1))
    }

    private var hasMore: Bool {
        displayedMonths.count < allMonths.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if allMonths.isEmpty {
                    ContentUnavailableView(
                        "기록 없음",
                        systemImage: "list.bullet.rectangle",
                        description: Text("저장한 항목이 여기 쌓여요.")
                    )
                } else {
                    historyList
                }
            }
            .animation(.smooth(duration: 0.3), value: allMonths.isEmpty)
            .toolbar {
                if allMonths.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PastMonthsView()
                        } label: {
                            Image(systemName: "calendar")
                                .accessibilityLabel("월별 보기")
                        }
                    }
                }
            }
            .navigationTitle("최근 기록")
        }
    }

    private var historyList: some View {
        List {
            ForEach(displayedMonths) { month in
                MonthSections(month: month)
            }

            footerSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private var footerSection: some View {
        Section {
            HStack {
                Spacer()
                Text(hasMore ? "↓ 이전 달 더 보기" : "처음 기록까지 표시됨")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .onAppear {
                if hasMore {
                    withAnimation(.smooth(duration: 0.3)) {
                        monthsBack += 1
                    }
                }
            }
        }
    }
}

struct MonthSections: View {
    let month: HistoryGrouping.MonthGroup
    @State private var editingEntry: SavedEntry?

    var body: some View {
        Group {
            Section {
                NavigationLink {
                    CSVFileView(csvFilename: month.csvFilename, monthTitle: month.title)
                } label: {
                    HStack {
                        Text("\(month.title) 합계")
                            .font(.subheadline)
                        Spacer()
                        Text("\(month.total.formatted(.number))원")
                            .font(.subheadline.monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(.primary)
                    .animation(.smooth(duration: 0.3), value: month.total)
                }
            }

            ForEach(month.days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            HistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(day.title)
                        .textCase(nil)
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            SavedEntryEditorView(entry: entry)
        }
    }
}

private struct HistoryRow: View {
    let entry: SavedEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.merchant).font(.body)
                if let category = entry.category {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(entry.amount.formatted(.number))원")
                .font(.body.monospacedDigit())
        }
        .contentShape(.rect)
    }
}

struct PastMonthsView: View {
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]

    private var months: [HistoryGrouping.MonthGroup] {
        HistoryGrouping.group(entries: entries)
    }

    var body: some View {
        Group {
            if months.isEmpty {
                ContentUnavailableView(
                    "기록 없음",
                    systemImage: "calendar",
                    description: Text("기록이 쌓이면 월별로 여기 정리돼요.")
                )
            } else {
                List {
                    ForEach(months) { month in
                        NavigationLink {
                            PastMonthDetailView(monthId: month.id)
                        } label: {
                            LabeledContent {
                                Text("\(month.total.formatted(.number))원")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(month.title)
                            }
                        }
                    }
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
            }
        }
        .animation(.smooth(duration: 0.3), value: months.isEmpty)
        .navigationTitle("월별 기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PastMonthDetailView: View {
    let monthId: DateComponents
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]

    private var month: HistoryGrouping.MonthGroup? {
        HistoryGrouping.group(entries: entries).first { $0.id == monthId }
    }

    var body: some View {
        Group {
            if let month {
                List {
                    MonthSections(month: month)
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
                .navigationTitle(month.title)
            } else {
                ContentUnavailableView(
                    "기록 없음",
                    systemImage: "list.bullet.rectangle",
                    description: Text("이 달의 모든 기록이 삭제됐어요.")
                )
            }
        }
        .animation(.smooth(duration: 0.3), value: month == nil)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: SavedEntry.self, inMemory: true)
}
