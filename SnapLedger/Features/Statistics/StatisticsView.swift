import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    /// Signal from ContentView to reset selection back to the current month.
    var resetNonce: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var settingsList: [AppSettings]

    @State private var selectedMonthID: DateComponents?
    @State private var categoryDetail: CategoryEntriesDetail?
    /// Trend filter selection; nil displays stacked categories.
    @State private var trendCategory: String?

    private var months: [StatisticsAggregation.MonthlyStats] {
        StatisticsAggregation.aggregate(entries: entries)
    }

    private var categoryPresets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    private var selectedMonth: StatisticsAggregation.MonthlyStats? {
        if let id = selectedMonthID, let match = months.first(where: { $0.id == id }) {
            return match
        }
        return months.first
    }

    /// Whether trend section remains visible when filter yields empty rows.
    private var overallTrendPoints: [StatisticsAggregation.TrendPoint] {
        StatisticsAggregation.trend(months: months)
    }

    private var trendPoints: [StatisticsAggregation.TrendPoint] {
        StatisticsAggregation.trend(months: months, category: trendCategory)
    }

    // Chart retains 6-month window; list trims leading zero months.
    private var chartPoints: [StatisticsAggregation.TrendPoint] {
        StatisticsAggregation.trend(months: months, trimLeadingZeros: false, category: trendCategory)
    }

    private var categoryChartPoints: [StatisticsAggregation.CategoryTrendPoint] {
        StatisticsAggregation.categoryTrend(months: months)
    }

    private var trendCategoryOptions: [String] {
        StatisticsAggregation.trendCategories(in: categoryChartPoints)
    }

    var body: some View {
        NavigationStack {
            Group {
                if months.isEmpty {
                    ContentUnavailableView(
                        "통계 없음",
                        systemImage: "chart.pie",
                        description: Text("저장한 항목이 쌓이면 여기 보여요.")
                    )
                } else {
                    statsContent
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: months.isEmpty)
            .navigationTitle("통계")
        }
        // Tab re-selection resets to latest month.
        .onChange(of: resetNonce) { _, _ in
            selectedMonthID = nil
        }
    }

    private var statsContent: some View {
        List {
            if !months.isEmpty {
                monthPickerSection
            }

            if let month = selectedMonth {
                summarySection(month: month)
                donutSection(month: month)
                breakdownSection(month: month)
            }

            if !overallTrendPoints.isEmpty {
                trendSection
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: selectedMonth?.id)
        .sheet(item: $categoryDetail) { detail in
            CategoryEntriesSheet(detail: detail)
                .presentationDetents([.medium, .large])
        }
    }

    // Step only between months with recorded entries.
    private var monthPickerSection: some View {
        Section {
            MonthNavigationRow(
                title: selectedMonth?.title ?? "",
                options: months.map { .init(key: $0.id, title: $0.title) },
                canStepBackward: selectedIndex.map { $0 + 1 < months.count } ?? false,
                canStepForward: selectedIndex.map { $0 > 0 } ?? false,
                stepBackward: { step(by: 1) },
                stepForward: { step(by: -1) },
                select: { selectedMonthID = $0 }
            )
        }
    }

    /// Sorted months descending, index 0 being the latest.
    private var selectedIndex: Int? {
        guard let id = selectedMonth?.id else { return nil }
        return months.firstIndex { $0.id == id }
    }

    private func step(by offset: Int) {
        guard let index = selectedIndex, months.indices.contains(index + offset) else { return }
        selectedMonthID = months[index + offset].id
    }

    private func summarySection(month: StatisticsAggregation.MonthlyStats) -> some View {
        Section {
            HStack {
                Text("\(month.title) 합계")
                    .font(.subheadline)
                Spacer()
                Text("\(month.total.formatted(.number))원")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText())
            }
            HStack {
                Text("건수")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(month.entryCount)건")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func donutSection(month: StatisticsAggregation.MonthlyStats) -> some View {
        Section {
            if month.slices.isEmpty {
                Text("이번 달 기록이 없어요.")
                    .foregroundStyle(.secondary)
            } else {
                CategoryDonutChart(slices: month.slices, total: month.total, presets: categoryPresets)
                    .frame(height: 240)
                    .padding(.vertical, 8)
            }
        } header: {
            Text("카테고리 비중")
                .textCase(nil)
        }
    }

    private func breakdownSection(month: StatisticsAggregation.MonthlyStats) -> some View {
        Section {
            ForEach(month.slices) { slice in
                Button {
                    categoryDetail = CategoryEntriesDetail(
                        category: slice.category,
                        monthKey: (month.id.year ?? 0) * 100 + (month.id.month ?? 0)
                    )
                } label: {
                    CategoryBreakdownRow(slice: slice)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("카테고리별 합계")
                .textCase(nil)
        } footer: {
            Text("카테고리를 누르면 항목을 볼 수 있어요.")
        }
    }

    private var trendSection: some View {
        Section {
            Picker("카테고리", selection: $trendCategory) {
                Text("전체").tag(String?.none)
                ForEach(trendCategoryOptions, id: \.self) { category in
                    Text(category).tag(String?.some(category))
                }
            }
            .pickerStyle(.menu)

            TrendChart(points: chartPoints)
                .frame(height: 200)
                .padding(.vertical, 8)

            if trendPoints.isEmpty {
                Text("최근 6개월에 이 카테고리 기록이 없어요.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trendPoints.reversed()) { point in
                    TrendRow(point: point)
                }
            }
        } header: {
            Text("월별 추세")
                .textCase(nil)
        }
    }
}

private struct CategoryDonutChart: View {
    let slices: [StatisticsAggregation.CategorySlice]
    let total: Int
    let presets: [String]

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("금액", slice.total),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("카테고리", slice.category))
            .annotation(position: .overlay) {
                if slice.share >= 0.05 {
                    Text(slice.share.formatted(.percent.precision(.fractionLength(0...0))))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        // Deterministic category color mapping.
        .chartForegroundStyleScale(mapping: color(for:))
        .chartLegend(position: .bottom, alignment: .center, spacing: 8)
        .chartBackground { proxy in
            // Center text within donut plot area.
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    // Center amount in donut with secondary label overlay.
                    Text("\(total.formatted(.number))원")
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                        .overlay(alignment: .bottom) {
                            Text("총 지출")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .alignmentGuide(.bottom) { $0[.top] }
                                .offset(y: 2)
                        }
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    private func color(for category: String) -> Color {
        CategoryColor.color(for: category, presets: presets)
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

private struct TrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [StatisticsAggregation.TrendPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("월", point.shortTitle),
                y: .value("합계", point.total)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Int.self) {
                        Text(trendAxisLabel(for: amount))
                            .font(.caption2)
                    }
                }
            }
        }
        // Animate bar height changes on data updates.
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: points.map(\.total))
    }
}

private func trendAxisLabel(for amount: Int) -> String {
    if amount >= 10_000 {
        let value = Double(amount) / 10_000
        return String(format: "%.0f만", value)
    }
    if amount >= 1_000 {
        let value = Double(amount) / 1_000
        return String(format: "%.0f천", value)
    }
    return "\(amount)"
}

private struct TrendRow: View {
    let point: StatisticsAggregation.TrendPoint

    var body: some View {
        HStack {
            Text(point.shortTitle)
                .font(.body)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(point.total.formatted(.number))원")
                    .font(.body.monospacedDigit())
                    .contentTransition(.numericText())
                deltaLabel
            }
        }
    }

    @ViewBuilder
    private var deltaLabel: some View {
        if let delta = point.deltaFromPrevious {
            let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "±")
            let magnitude = abs(delta).formatted(.number)
            let ratioText: String = {
                guard let ratio = point.ratioFromPrevious else { return "" }
                let percent = abs(ratio).formatted(.percent.precision(.fractionLength(0...1)))
                return " (\(percent))"
            }()
            Text("\(sign)\(magnitude)원\(ratioText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color(for: delta))
        } else {
            Text("기준 월")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for delta: Int) -> Color {
        if delta > 0 { return .red }
        if delta < 0 { return .green }
        return .secondary
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: SavedEntry.self, inMemory: true)
}
