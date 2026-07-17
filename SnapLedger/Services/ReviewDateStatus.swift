import Foundation

/// 검토 화면 날짜 필드의 상태 판정. 카드 결제 스크린샷은 보통 오늘·어제라
/// 그 범위를 벗어난 날짜는 오입력 가능성이 있어 경고 대상이다:
/// `tooOld`(어제 이전 = 그저께 이하), `future`(오늘 이후 = 내일 이상).
/// UI 문자열은 뷰가 소유하고 여기서는 로케일 독립적인 판정만 한다
/// (`CategoryValidation.isOffPreset`과 같은 경고-판정 분리 패턴).
enum ReviewDateStatus {
    case today
    case yesterday
    case tooOld
    case future

    var isWarning: Bool { self == .tooOld || self == .future }
}

enum ReviewDateCheck {
    /// `date`가 속한 '일'을 `now`가 속한 '일' 기준으로 분류한다. 시각은 무시하고
    /// 캘린더 일 단위로만 비교하므로 정오/자정 등 시각 차이에 흔들리지 않는다.
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
