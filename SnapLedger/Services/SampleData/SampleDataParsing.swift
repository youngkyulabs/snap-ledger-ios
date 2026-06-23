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

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 정산 CSV(`종류,항목,계좌,방향,금액,메모`) → ReconciliationDraft.
    /// 잔액(기초/기말/이자)은 accountName=항목(별칭)으로 그룹화하고, 기말 행이 없으면 기말=기초.
    static func parseReconciliationDraft(_ csv: String) -> ReconciliationDraft {
        let rows = ReconciliationCSVParser.parse(csv).rows
        var draft = ReconciliationDraft()
        var balanceOrder: [String] = []
        var balanceByName: [String: BalanceDraft] = [:]

        for row in rows {
            applyRow(row, into: &draft, balanceOrder: &balanceOrder, balanceByName: &balanceByName)
        }

        draft.balances = balanceOrder.map { name in
            var balance = balanceByName[name] ?? BalanceDraft(accountName: name)
            // 기말 행이 없던(=0으로 남은) 진행 중 달은 기말=기초로 중립 처리.
            if !hasClosingRow(rows, accountName: name) {
                balance.closing = balance.opening
            }
            return balance
        }
        return draft
    }

    private static func applyRow(
        _ row: ReconciliationCSVRow,
        into draft: inout ReconciliationDraft,
        balanceOrder: inout [String],
        balanceByName: inout [String: BalanceDraft]
    ) {
        switch row.kind {
        case .income:
            draft.incomes.append(IncomeItemDraft(title: row.title ?? "", amount: row.amount ?? 0,
                                                 sortOrder: draft.incomes.count))
        case .creditCard:
            draft.cards.append(CardUsageItemDraft(title: row.title ?? "", amount: row.amount ?? 0,
                                                  sortOrder: draft.cards.count))
        case .savings:
            draft.savings.append(SavingsItemDraft(title: row.title ?? "", amount: row.amount ?? 0,
                                                  sortOrder: draft.savings.count))
        case .cashAdjustment:
            draft.adjustments.append(AdjustmentDraft(
                title: row.title ?? "",
                direction: row.direction ?? .withdrawal,
                amount: row.amount ?? 0,
                note: row.note,
                sortOrder: draft.adjustments.count))
        case .monthNote:
            draft.note = row.note ?? ""
        case .openingBalance, .closingBalance, .interest:
            applyBalanceRow(row, balanceOrder: &balanceOrder, balanceByName: &balanceByName)
        }
    }

    private static func applyBalanceRow(
        _ row: ReconciliationCSVRow,
        balanceOrder: inout [String],
        balanceByName: inout [String: BalanceDraft]
    ) {
        let name = row.title ?? row.account ?? ""
        if balanceByName[name] == nil {
            balanceByName[name] = BalanceDraft(accountName: name, sortOrder: balanceOrder.count)
            balanceOrder.append(name)
        }
        let amount = row.amount ?? 0
        switch row.kind {
        case .openingBalance: balanceByName[name]?.opening = amount
        case .closingBalance: balanceByName[name]?.closing = amount
        case .interest: balanceByName[name]?.interest = amount
        default: break
        }
    }

    private static func hasClosingRow(_ rows: [ReconciliationCSVRow], accountName: String) -> Bool {
        rows.contains { $0.kind == .closingBalance && ($0.title ?? $0.account ?? "") == accountName }
    }
}
#endif
