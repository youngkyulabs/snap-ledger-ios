import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var monthsBack: Int = 0
    @State private var isLoadingMore = false

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
        // 사용자가 스크롤을 맨 위까지 끌어올리면 펼쳐둔 이전 달들을 접는다.
        // contentInsets를 보정해 rubber band 영역에서도 0 이하로 평가되도록.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y - geometry.contentInsets.top
        } action: { _, offset in
            if offset <= 0 {
                collapseIfPossible()
            }
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        if isLoadingMore {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("이전 달 불러오는 중…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else if hasMore {
            Section {
                Text("↓ 이전 달 더 보기")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // monthsBack 변경 시 새 view 인스턴스로 재생성되도록 강제.
                    // 그래야 SwiftUI lazy 캐싱에 막히지 않고 사용자가 다시
                    // 스크롤 끝에 도달했을 때 onAppear가 재발화한다.
                    .id("trigger-\(monthsBack)")
                    .onAppear(perform: loadMoreIfNeeded)
            }
        } else {
            Section {
                Text("처음 기록까지 표시됨")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard hasMore, !isLoadingMore else { return }
        Task {
            isLoadingMore = true
            // 즉시 추가되면 사용자가 "방금 더 불러왔구나"를 인지할 시간이 없어
            // 의도적 딜레이를 둔다. ProgressView가 잠깐 보였다가 새 달이 등장.
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.smooth(duration: 0.3)) {
                monthsBack += 1
            }
            isLoadingMore = false
        }
    }

    private func collapseIfPossible() {
        guard monthsBack > 0, !isLoadingMore else { return }
        withAnimation(.smooth(duration: 0.3)) {
            monthsBack = 0
        }
    }
}

struct MonthSections: View {
    let month: HistoryGrouping.MonthGroup
    @State private var editingEntry: SavedEntry?

    var body: some View {
        Group {
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            CSVFileView(
                                csvFilename: month.csvFilename,
                                monthTitle: month.title
                            )
                        } label: {
                            Image(systemName: "doc.text")
                                .accessibilityLabel("CSV 파일 보기")
                        }
                    }
                }
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
