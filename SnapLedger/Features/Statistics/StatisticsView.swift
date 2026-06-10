import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var settingsList: [AppSettings]

    @State private var selectedMonthID: DateComponents?

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

    private var trendPoints: [StatisticsAggregation.TrendPoint] {
        StatisticsAggregation.trend(months: months)
    }

    // 차트는 항상 6개월 슬롯을 그대로 보여주고, 기록 없는 달은 빈 막대로 둔다.
    // 리스트만 leading-zero trim이 적용된다 (trendPoints).
    private var chartPoints: [StatisticsAggregation.TrendPoint] {
        StatisticsAggregation.trend(months: months, trimLeadingZeros: false)
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

            if !trendPoints.isEmpty {
                trendSection
            }
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: selectedMonth?.id)
    }

    // 화살표는 기록이 있는 달 사이만 이동 (빈 달은 통계가 없으므로 건너뛴다).
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

    /// months는 최신순 정렬 — index 0이 가장 최근 달.
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
                CategoryBreakdownRow(slice: slice)
            }
        } header: {
            Text("카테고리별 합계")
                .textCase(nil)
        }
    }

    private var trendSection: some View {
        Section {
            TrendChart(points: chartPoints)
                .frame(height: 200)
                .padding(.vertical, 8)
            ForEach(trendPoints.reversed()) { point in
                TrendRow(point: point)
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
        // 카테고리별 색상을 고정 매핑한다. foregroundStyle(by:)의 자동 매핑은
        // 슬라이스 순서가 바뀌면 같은 카테고리도 색이 달라져, 월 전환 보간 시
        // 색이 흐르는 어색함의 원인이 된다.
        .chartForegroundStyleScale(mapping: color(for:))
        .chartLegend(position: .bottom, alignment: .center, spacing: 8)
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text("\(total.formatted(.number))원")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text("총 지출")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }
}

private struct TrendChart: View {
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
                        Text(Self.compactLabel(for: amount))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private static func compactLabel(for amount: Int) -> String {
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
