import SwiftUI
import SwiftData
import Charts

/// Category share and monthly trend sections of the ledger list.
struct StatisticsSections: View {
    /// Month shown, supplied by the shared selector above the list.
    let month: Int
    /// Opens the per-category totals sheet.
    let openCategoryTotals: () -> Void

    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]
    @Query private var settingsList: [AppSettings]

    /// Trend filter selection; nil displays every category combined.
    @State private var trendCategory: String?

    private var months: [StatisticsAggregation.MonthlyStats] {
        StatisticsAggregation.aggregate(entries: entries)
    }

    private var categoryPresets: [String] {
        settingsList.first?.categoryPresets ?? AppSettings.defaultPresets
    }

    private var selectedMonth: StatisticsAggregation.MonthlyStats? {
        months.first { ($0.id.year ?? 0) * 100 + ($0.id.month ?? 0) == month }
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

    private var trendCategoryOptions: [String] {
        StatisticsAggregation.trendCategories(in: StatisticsAggregation.categoryTrend(months: months))
    }

    var body: some View {
        Group {
            donutSection
            if !overallTrendPoints.isEmpty {
                trendSection
            }
        }
    }

    private var donutSection: some View {
        Section {
            if let stats = selectedMonth, !stats.slices.isEmpty {
                Button(action: openCategoryTotals) {
                    CategoryDonutChart(slices: stats.slices, total: stats.total, presets: categoryPresets)
                        .frame(height: 240)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text("이 달에는 기록이 없어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text("카테고리 비중").textCase(nil)
        } footer: {
            if let stats = selectedMonth, !stats.slices.isEmpty {
                Text("누르면 카테고리별 합계를 볼 수 있어요.")
            }
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
            Text("월별 추세").textCase(nil)
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
