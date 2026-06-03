import SwiftUI

/// 카테고리 색 매핑(통계 도넛·예산 진행 공유). presets 인덱스 기반 + 미등록 카테고리는
/// 이름의 결정적 해시(StatisticsAggregation.colorIndex)로 색을 고정한다.
enum CategoryColor {
    /// 시인성 좋게 잘 구분되는 12색 팔레트.
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
