#if DEBUG
import Foundation

/// 임베드 지출 한 행을 도메인 값으로.
struct ExpenseSeed: Equatable {
    let date: Date
    let merchant: String
    let category: String?
    let amount: Int
    let note: String?
}

/// 임베드 CSV 텍스트를 도메인 seed로 바꾸는 pure 변환. SwiftData·시스템 의존 없음.
enum SampleDataParsing {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 지출 CSV(`날짜,설명,카테고리,금액,메모`) → ExpenseSeed 목록. 헤더·파싱 불가 행은 스킵.
    static func parseExpenses(_ csv: String) -> [ExpenseSeed] {
        let rows = CSVParser.parse(csv)
        guard !rows.isEmpty else { return [] }
        var seeds: [ExpenseSeed] = []
        for row in rows.dropFirst() {
            guard row.count >= 4,
                  let date = dateFormatter.date(from: row[0].trimmingCharacters(in: .whitespaces)),
                  let amount = Int(row[3].replacingOccurrences(of: ",", with: "")) else {
                continue
            }
            let merchant = row[1].trimmingCharacters(in: .whitespaces)
            let category = nonEmpty(row[2])
            let note = row.count >= 5 ? nonEmpty(row[4]) : nil
            seeds.append(ExpenseSeed(date: date, merchant: merchant, category: category, amount: amount, note: note))
        }
        return seeds
    }

    static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
