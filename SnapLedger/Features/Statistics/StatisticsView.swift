import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query(sort: \SavedEntry.date, order: .reverse) private var entries: [SavedEntry]

    @State private var selectedMonthID: DateComponents?

    private var months: [StatisticsAggregation.MonthlyStats] {
        StatisticsAggregation.aggregate(entries: entries)
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
            .animation(.smooth(duration: 0.3), value: months.isEmpty)
            .navigationTitle("통계")
        }
    }

    private var statsContent: some View {
        List {
            if months.count > 1 {
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
        .animation(.smooth(duration: 0.35), value: selectedMonth?.id)
    }

    private var monthPickerSection: some View {
        Section {
            Picker("월 선택", selection: Binding(
                get: { selectedMonth?.id ?? months[0].id },
                set: { selectedMonthID = $0 }
            )) {
                ForEach(months) { month in
                    Text(month.title).tag(month.id)
                }
            }
            .pickerStyle(.menu)
        }
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
                CategoryDonutChart(slices: month.slices, total: month.total)
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
            TrendChart(points: trendPoints)
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

    // SectorMark.annotation 은 슬라이스 중심의 angular position 에 묶여 있어
    // 평소에 % 라벨을 띄워두면 월 전환 보간 시 라벨도 같이 회전한다.
    // 대신 사용자가 도넛을 길게 누르고 있는 동안에만 % 를 fade-in 한다.
    @State private var isShowingLabels = false

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
                        .opacity(isShowingLabels ? 1 : 0)
                }
            }
        }
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
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.05, maximumDistance: .infinity) {
            // 누름 확정 액션은 사용 안 함 — onPressingChanged 로 finger down/up 만 추적
        } onPressingChanged: { pressing in
            withAnimation(.smooth(duration: pressing ? 0.12 : 0.2)) {
                isShowingLabels = pressing
            }
        }
        .accessibilityHint("길게 누르면 카테고리별 퍼센트가 보여요.")
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
