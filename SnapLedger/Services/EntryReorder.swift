import Foundation

/// Helper for recalculating timestamps during entry reordering.
enum EntryReorder {
    /// Sorts timestamps descending and ensures strict monotonicity.
    static func descendingTimestamps(from dates: [Date]) -> [Date] {
        var result: [Date] = []
        for value in dates.sorted(by: >) {
            if let last = result.last, value >= last {
                result.append(last.addingTimeInterval(-0.001))
            } else {
                result.append(value)
            }
        }
        return result
    }
}
