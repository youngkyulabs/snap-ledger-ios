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
        // Bypass pagination during active search to display all matches.
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
            // Standard searchable collapses on scroll.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "설명·카테고리·메모·금액 검색"
            )
            .toolbar {
                // Opens the month calendar.
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            HistoryCalendarView()
                        } label: {
                            Image(systemName: "calendar")
                                .accessibilityLabel("달력")
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
                MonthSections(
                    month: month,
                    editingEntry: $editingEntry,
                    onMove: moveEntries,
                    // Disable reordering while search filter is active.
                    reorderEnabled: !isSearching
                )
            }

            footerSection
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        // Sheet at parent level avoids accidental dismissal during query updates.
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
            // Hide pagination footer during active search.
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
                    // Force view identity update to retrigger onAppear on pagination.
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
            // Brief delay provides visible feedback before appending next month.
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
    /// Drag-and-drop reordering restricted to the same calendar day.
    let onMove: (HistoryGrouping.DayGroup, IndexSet, Int) -> Void
    /// Reordering enabled only when displaying the full list without active search.
    var reorderEnabled = true

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
                    .moveDisabled(!reorderEnabled)
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

struct HistoryRow: View {
    let entry: SavedEntry

    private var note: String? {
        guard let note = entry.note, !note.isEmpty else { return nil }
        return note
    }

    private var category: String? {
        guard let category = entry.category, !category.isEmpty else { return nil }
        return category
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.merchant).font(.body)
                if category != nil || note != nil {
                    HStack(spacing: 6) {
                        if let category {
                            CategoryChip(category: category)
                        }
                        if let note {
                            NotePreview(note: note)
                        }
                    }
                }
            }
            Spacer()
            Text("\(entry.amount.formatted(.number))원")
                .font(.body.monospacedDigit())
        }
        .contentShape(.rect)
    }
}

/// Coordinates saving updated entry ordering.
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
            onError((error as? any LocalizedError)?.errorDescription ?? error.localizedDescription)
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
