import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var monthsBack: Int = 0
    @State private var isLoadingMore = false
    @State private var editingEntry: SavedEntry?
    @State private var reorderError: String?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredEntries: [SavedEntry] {
        EntrySearch.filter(entries, query: searchText)
    }

    private var allMonths: [HistoryGrouping.MonthGroup] {
        HistoryGrouping.group(entries: filteredEntries)
    }

    private var displayedMonths: [HistoryGrouping.MonthGroup] {
        // 검색 중엔 페이지네이션을 우회하고 매칭되는 모든 달을 보여준다.
        isSearching ? allMonths : Array(allMonths.prefix(monthsBack + 1))
    }

    private var hasMore: Bool {
        !isSearching && displayedMonths.count < allMonths.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "기록 없음",
                        systemImage: "list.bullet.rectangle",
                        description: Text("저장한 항목이 여기 쌓여요.")
                    )
                } else if allMonths.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    historyList
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: allMonths.isEmpty)
            .searchable(text: $searchText, prompt: "설명·카테고리·메모 검색")
            .toolbar {
                // 1개월일 때도 월별 보기로 진입할 수 있어야 CSVFileView에 도달 가능.
                if !entries.isEmpty {
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
                MonthSections(month: month, editingEntry: $editingEntry, onMove: moveEntries)
            }

            footerSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        // sheet을 부모 레벨에 두어야 자식(MonthSections)이 무한 스크롤이나
        // SwiftData @Query 갱신으로 재구성될 때도 dismiss되지 않는다.
        .sheet(item: $editingEntry) { entry in
            SavedEntryEditorView(entry: entry)
        }
        .reorderFailureAlert($reorderError)
    }

    private func moveEntries(in day: HistoryGrouping.DayGroup, from source: IndexSet, to destination: Int) {
        var reordered = day.entries
        reordered.move(fromOffsets: source, toOffset: destination)
        EntryReorderAction.perform(reordered, context: modelContext) { reorderError = $0 }
    }

    @ViewBuilder
    private var footerSection: some View {
        if isSearching {
            // 검색 결과에는 '더 보기'/'끝까지 봤어요' 푸터를 숨긴다.
            EmptyView()
        } else if isLoadingMore {
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
                Text("처음 기록까지 모두 봤어요")
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
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                monthsBack += 1
            }
            isLoadingMore = false
        }
    }
}

struct MonthSections: View {
    let month: HistoryGrouping.MonthGroup
    @Binding var editingEntry: SavedEntry?
    /// 같은 날짜 안 드래그 이동 (행을 꾹 눌러 재정렬). day 섹션별 ForEach에 붙어 섹션 간 이동은 불가능.
    let onMove: (HistoryGrouping.DayGroup, IndexSet, Int) -> Void

    var body: some View {
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
                .onMove { source, destination in
                    onMove(day, source, destination)
                }
            } header: {
                Text(day.title)
                    .textCase(nil)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: SavedEntry

    private var hasNote: Bool {
        !(entry.note?.isEmpty ?? true)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.merchant).font(.body)
                if let category = entry.category {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
            }
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
        .contentShape(.rect)
    }
}

struct PastMonthsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: months.isEmpty)
        .navigationTitle("월별 기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PastMonthDetailView: View {
    let monthId: DateComponents
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var editingEntry: SavedEntry?
    @State private var reorderError: String?

    private var month: HistoryGrouping.MonthGroup? {
        HistoryGrouping.group(entries: entries).first { $0.id == monthId }
    }

    var body: some View {
        Group {
            if let month {
                List {
                    MonthSections(month: month, editingEntry: $editingEntry, onMove: moveEntries)
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
                .navigationTitle(month.title)
                .navigationSubtitle("합계 \(month.total.formatted(.number))원")
                .sheet(item: $editingEntry) { entry in
                    SavedEntryEditorView(entry: entry)
                }
                .reorderFailureAlert($reorderError)
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: month == nil)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moveEntries(in day: HistoryGrouping.DayGroup, from source: IndexSet, to destination: Int) {
        var reordered = day.entries
        reordered.move(fromOffsets: source, toOffset: destination)
        EntryReorderAction.perform(reordered, context: modelContext) { reorderError = $0 }
    }
}

/// 드래그 순서 변경의 저장 흐름 (최근 기록·월별 상세 공용).
@MainActor
private enum EntryReorderAction {
    static func perform(
        _ reordered: [SavedEntry],
        context: ModelContext,
        onError: @escaping (String) -> Void
    ) {
        do {
            try SaveCoordinator(categoryLearner: CategoryLearner())
                .reorder(reordered, in: context)
        } catch {
            onError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

private extension View {
    func reorderFailureAlert(_ message: Binding<String?>) -> some View {
        alert(
            "순서 변경 실패",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("확인", role: .cancel) { message.wrappedValue = nil }
        } message: { text in
            Text(text)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: SavedEntry.self, inMemory: true)
}
