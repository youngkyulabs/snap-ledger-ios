import Foundation

/// 같은 날짜 안 항목의 표시 순서 변경을 savedAt 재배열로 표현하기 위한 헬퍼.
/// savedAt은 기록 탭의 일내(日內) 정렬 키이자 CSV 행 순서 키(월별 export가
/// savedAt 오름차순으로 쓰고, import가 행 순서대로 복원)라서, 값을 새로 만들지
/// 않고 기존 값들을 재배열하면 순서 변경이 파일까지 그대로 왕복한다.
enum EntryReorder {
    /// 입력 날짜들의 multiset을 내림차순으로 정렬해 돌려준다.
    /// 새 표시 순서의 i번째 항목에 i번째 값을 주면 표시 정렬(내림차순)이 그 순서가 된다.
    /// 중복 값은 순서가 비결정적이 되지 않게 직전 값보다 1ms 아래로 민다.
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
