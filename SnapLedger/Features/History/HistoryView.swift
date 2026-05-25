import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var monthsBack: Int = 0
    @State private var isLoadingMore = false
    @State private var isUserInteracting = false
    @State private var editingEntry: SavedEntry?

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
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: allMonths.isEmpty)
            .toolbar {
                // 1개월일 때도 월별 보기로 진입할 수 있어야 CSVFileView에 도달 가능.
                if !allMonths.isEmpty {
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
                MonthSections(month: month, editingEntry: $editingEntry)
            }

            footerSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        // 사용자가 스크롤을 맨 위까지 *직접* 끌어올릴 때만 펼쳐둔 이전 달들을 접는다.
        // 사용자 제스처가 아닌 자동 offset=0(컨텐츠가 화면을 못 채우는 경우)에서
        // collapse가 발화하면, "이전 달 불러오기 → 접힘 → 다시 불러오기" 오실레이션
        // 으로 이어진다. isUserInteracting으로 게이팅해 그 사이클을 끊는다.
        .onScrollPhaseChange { _, newPhase in
            isUserInteracting = (newPhase == .interacting || newPhase == .tracking)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y - geometry.contentInsets.top
        } action: { _, offset in
            if offset <= 0, isUserInteracting {
                collapseIfPossible()
            }
        }
        // sheet을 부모 레벨에 두어야 자식(MonthSections)이 무한 스크롤이나
        // SwiftData @Query 갱신으로 재구성될 때도 dismiss되지 않는다.
        .sheet(item: $editingEntry) { entry in
            SavedEntryEditorView(entry: entry)
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
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                monthsBack += 1
            }
            isLoadingMore = false
        }
    }

    private func collapseIfPossible() {
        guard monthsBack > 0, !isLoadingMore else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            monthsBack = 0
        }
    }
}

struct MonthSections: View {
    let month: HistoryGrouping.MonthGroup
    @Binding var editingEntry: SavedEntry?

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
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @State private var editingEntry: SavedEntry?

    private var month: HistoryGrouping.MonthGroup? {
        HistoryGrouping.group(entries: entries).first { $0.id == monthId }
    }

    var body: some View {
        Group {
            if let month {
                List {
                    MonthSections(month: month, editingEntry: $editingEntry)
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
                .navigationTitle(month.title)
                .navigationSubtitle("합계 \(month.total.formatted(.number))원")
                .sheet(item: $editingEntry) { entry in
                    SavedEntryEditorView(entry: entry)
                }
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
}

#Preview {
    HistoryView()
        .modelContainer(for: SavedEntry.self, inMemory: true)
}
