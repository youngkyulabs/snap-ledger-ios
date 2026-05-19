import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]

    private var months: [HistoryGrouping.MonthGroup] {
        HistoryGrouping.group(entries: entries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let latest = months.first {
                    MonthDetailContent(
                        month: latest,
                        showsPastMonthsLink: months.count > 1
                    )
                } else {
                    ContentUnavailableView(
                        "기록 없음",
                        systemImage: "list.bullet.rectangle",
                        description: Text("저장한 항목이 여기 쌓여요.")
                    )
                }
            }
            .animation(.smooth(duration: 0.3), value: months.isEmpty)
            .navigationTitle("기록")
        }
    }
}

struct MonthDetailContent: View {
    let month: HistoryGrouping.MonthGroup
    var showsPastMonthsLink: Bool = false

    @State private var editingEntry: SavedEntry?

    var body: some View {
        List {
            Section {
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

            if showsPastMonthsLink {
                Section {
                    NavigationLink {
                        PastMonthsView()
                    } label: {
                        Label("이전 기록", systemImage: "calendar")
                    }
                }
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CSVFileView(csvFilename: month.csvFilename, monthTitle: month.title)
                } label: {
                    Image(systemName: "doc.text")
                        .accessibilityLabel("CSV 파일 보기")
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

    private var pastMonths: [HistoryGrouping.MonthGroup] {
        Array(HistoryGrouping.group(entries: entries).dropFirst())
    }

    var body: some View {
        Group {
            if pastMonths.isEmpty {
                ContentUnavailableView(
                    "이전 기록 없음",
                    systemImage: "calendar",
                    description: Text("이전 달 기록이 쌓이면 여기 보여요.")
                )
            } else {
                List {
                    ForEach(pastMonths) { month in
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
        .animation(.smooth(duration: 0.3), value: pastMonths.isEmpty)
        .navigationTitle("이전 기록")
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
                MonthDetailContent(month: month)
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
