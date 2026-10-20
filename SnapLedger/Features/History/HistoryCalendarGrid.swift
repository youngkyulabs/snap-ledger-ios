import SwiftUI

/// Weekday header plus a fixed 6×7 month grid that slides between months.
struct HistoryCalendarGrid: View {
    let monthKey: Int
    let totals: [Int: Int]
    let today: HistoryCalendar.Day
    let selection: HistoryCalendar.Day?
    let movingForward: Bool
    let cellHeight: CGFloat
    let onSelect: (HistoryCalendar.Day) -> Void

    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(name == "일" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                }
            }
            // Only the dates slide; the weekday header stays put.
            ZStack {
                monthGrid
                    .id(monthKey)
                    .transition(.push(from: movingForward ? .trailing : .leading))
            }
            .clipped()
        }
    }

    private var monthGrid: some View {
        let cells = HistoryCalendar.cells(monthKey: monthKey)
        return VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { weekday in
                        if let day = cells[week * 7 + weekday] {
                            dayCell(HistoryCalendar.Day(monthKey: monthKey, day: day))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: HistoryCalendar.Day) -> some View {
        let total = totals[day.day]
        let state = HistoryCalendar.state(of: day, today: today, hasEntries: total != nil)
        let label = DayCellLabel(
            day: day.day,
            total: total ?? 0,
            state: state,
            isToday: day == today,
            isSelected: day == selection,
            height: cellHeight
        )
        let accessibilityText = HistoryCalendar.accessibilityLabel(for: day, total: total, isToday: day == today)
        if state == .recorded {
            Button { onSelect(day) } label: { label }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(day == selection ? [.isButton, .isSelected] : .isButton)
        } else {
            // Not a button, so the empty and future colors are not dimmed further.
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }
}

private struct DayCellLabel: View {
    let day: Int
    let total: Int
    let state: HistoryCalendar.DayState
    let isToday: Bool
    let isSelected: Bool
    let height: CGFloat
    @ScaledMetric(relativeTo: .caption2) private var amountSize: CGFloat = 10

    private var numberStyle: AnyShapeStyle {
        switch state {
        case .recorded: AnyShapeStyle(.primary)
        case .empty: AnyShapeStyle(.secondary)
        case .future: AnyShapeStyle(.quaternary)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(numberStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(total > 0 ? total.formatted(.number) : " ")
                // Capped so six-digit amounts in neighboring cells never touch.
                .font(.system(size: min(amountSize, 12)).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.2))
            } else if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .contentShape(.rect)
    }
}
