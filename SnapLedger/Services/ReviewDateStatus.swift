import Foundation

/// Status classification for transaction date on review screen.
enum ReviewDateStatus {
    case today
    case yesterday
    case tooOld
    case future

    var isWarning: Bool { self == .tooOld || self == .future }
}

enum ReviewDateCheck {
    /// Classifies date relative to reference date.
    static func status(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReviewDateStatus {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return .today
        }
        if day > today { return .future }
        if day == today { return .today }
        if day == yesterday { return .yesterday }
        return .tooOld
    }
}
