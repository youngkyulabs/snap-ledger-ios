import SwiftUI
import SwiftData

/// Month calendar of daily spending; the selected day's entries sit below it.
struct HistoryCalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.savedAt, order: .reverse) private var entries: [SavedEntry]
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 48

    @State private var displayedMonth = HistoryCalendar.today().monthKey
    @State private var selection: HistoryCalendar.Day?
    @State private var movingForward = true
    @State private var editingEntry: SavedEntry?
    @State private var didSetInitialSelection = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
    }()

    private var motion: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }

    private var today: HistoryCalendar.Day { HistoryCalendar.today() }
    private var monthKeys: [Int] { HistoryCalendar.monthRange(entries, today: today) }
    private var totals: [Int: Int] { HistoryCalendar.dailyTotals(entries, monthKey: displayedMonth) }
    private var monthTotal: Int { totals.values.reduce(0, +) }

    var body: some View {
        List {
            Section {
                MonthNavigationRow(
                    title: ledgerMonthLabel(displayedMonth),
                    options: monthKeys.map { .init(key: $0, title: ledgerMonthLabel($0)) },
                    canStepBackward: displayedMonth > (monthKeys.last ?? displayedMonth),
                    canStepForward: displayedMonth < (monthKeys.first ?? displayedMonth),
                    stepBackward: { showMonth(CategoryBudgetStore.previousMonthKey(displayedMonth)) },
                    stepForward: { showMonth(CategoryBudgetStore.nextMonthKey(displayedMonth)) },
                    select: showMonth
                )
            }
            calendarSection
            daySection
        }
        .navigationTitle("달력")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CSVFileView(
                        csvFilename: HistoryCalendar.csvFilename(monthKey: displayedMonth),
                        monthTitle: ledgerMonthLabel(displayedMonth)
                    )
                } label: {
                    Image(systemName: "doc.text")
                        .accessibilityLabel("CSV 파일 보기")
                }
                .disabled(totals.isEmpty)
            }
        }
        .sheet(item: $editingEntry) { entry in
            SavedEntryEditorView(entry: entry)
        }
        .onAppear(perform: setInitialSelection)
    }

    private var calendarSection: some View {
        Section {
            HistoryCalendarGrid(
                monthKey: displayedMonth,
                totals: totals,
                today: today,
                selection: selection,
                movingForward: movingForward,
                cellHeight: cellHeight
            ) { day in
                withAnimation(motion) { selection = day }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("이번 달 합계")
                Spacer()
                Text("\(monthTotal.formatted(.number))원")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .textCase(nil)
        } footer: {
            Text("기록이 있는 날짜를 누르면 그날 쓴 내역을 볼 수 있어요.")
        }
    }

    private var daySection: some View {
        let dayEntries = selection.map { HistoryCalendar.entries(on: $0, from: entries) } ?? []
        return Section {
            if selection == nil {
                Text("날짜를 누르면 그날 내역이 보여요")
                    .foregroundStyle(.secondary)
            } else if dayEntries.isEmpty {
                Text("이 날은 기록이 없어요")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayEntries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            // Overlapping old and new headers fade without sharing geometry.
            ZStack {
                HStack {
                    Text(selection.map(title(of:)) ?? " ")
                    Spacer()
                    if selection != nil {
                        Text("\(dayEntries.reduce(0) { $0 + $1.amount }.formatted(.number))원")
                            .monospacedDigit()
                    }
                }
                .id(selection)
                .transition(.opacity)
            }
            .textCase(nil)
        }
    }

    private func title(of day: HistoryCalendar.Day) -> String {
        let first = CategoryBudgetStore.date(from: day.monthKey)
        let date = Calendar.current.date(byAdding: .day, value: day.day - 1, to: first) ?? first
        return Self.dayFormatter.string(from: date)
    }

    /// Applies the direction first, then animates the month on the next tick; List drops the animation when both land together.
    private func showMonth(_ key: Int) {
        guard key != displayedMonth else { return }
        movingForward = key > displayedMonth
        Task { @MainActor in
            withAnimation(motion) { displayedMonth = key }
        }
    }

    private func setInitialSelection() {
        guard !didSetInitialSelection else { return }
        didSetInitialSelection = true
        guard let pick = HistoryCalendar.initialSelection(entries, today: today) else { return }
        selection = pick
        displayedMonth = pick.monthKey
    }
}
