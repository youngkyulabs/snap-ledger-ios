import SwiftUI

/// Color mapping for categories using preset index or deterministic hash.
enum CategoryColor {
    /// 12-color palette chosen for visual distinction.
    static let palette: [Color] = [
        .orange, .blue, .pink, .green, .purple, .teal,
        .red, .indigo, .brown, .cyan, .mint, .yellow,
    ]

    static func color(for category: String, presets: [String]) -> Color {
        if category == StatisticsAggregation.uncategorizedLabel {
            return Color(.systemGray3)
        }
        let index = StatisticsAggregation.colorIndex(
            for: category, presets: presets, paletteCount: palette.count
        )
        return palette[index]
    }
}
