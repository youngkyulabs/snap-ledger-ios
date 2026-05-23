import Foundation

struct EnrichedTransaction: Sendable, Equatable {
    var base: PaymentTransaction
    var merchantCandidates: [String]
    var amountCandidates: [Int]
}

enum CandidateHeuristics {
    private static let amountExcludeKeywords: [String] = [
        "누적", "한도", "잔액", "사용가능", "포인트", "적립",
        "마일리지", "캐시백", "부가세", "과세물품가액", "월 사용액",
    ]

    // MARK: - payment signal gate

    /// 풍경/문서 등 결제와 무관한 이미지에서 LLM이 환각하는 것을 막기 위한 사전 게이트.
    /// 통화 표기·콤마 천 단위 금액·결제 키워드 중 하나라도 보이면 통과시키고,
    /// 어느 것도 없으면 추출을 건너뛴다.
    private static let paymentKeywords: [String] = [
        "승인", "일시불", "할부", "일반승인", "결제",
        "합계", "총액", "총 금액", "결제금액", "영수증",
        "현금영수증", "카드사용", "체크카드", "신용카드",
    ]

    private static let paymentSignalRegex: NSRegularExpression? = try? NSRegularExpression(
        // 1) 콤마 천 단위 금액(5,000)
        // 2) 숫자 + 원/₩/KRW
        // 3) ₩123, KRW123
        pattern: #"\d{1,3}(?:,\d{3})+|\d+\s*(?:원|₩|KRW)|[₩]\s*\d+|KRW\s*\d+"#,
        options: [.caseInsensitive]
    )

    static func hasPaymentSignal(_ ocrText: String) -> Bool {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let regex = paymentSignalRegex {
            let ns = trimmed as NSString
            if regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil {
                return true
            }
        }
        return paymentKeywords.contains { trimmed.contains($0) }
    }

    /// 콤마-포맷된 KRW (5,000) 또는 명시적 원 suffix가 붙은 정수만 매치.
    /// 단일 \d+ 매치는 날짜/시간/번호와 혼동되므로 제외.
    private static let amountRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d{1,3}(?:,\d{3})+|\d+(?=\s*원))"#
    )

    static func amounts(from ocrText: String, limit: Int = 5) -> [Int] {
        guard let regex = amountRegex else { return [] }
        let ns = ocrText as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: ocrText, range: fullRange)

        var seen = Set<Int>()
        var result: [Int] = []
        for match in matches {
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let raw = ns.substring(with: valueRange).replacingOccurrences(of: ",", with: "")
            guard let value = Int(raw), value > 0 else { continue }

            // 매치 직전 12 chars에 제외 키워드가 있으면 skip (라인 전체가 아니라
            // 직전 토큰만 — "총액 10,700 부가세 973"에서 총액 10,700은 살리고 973만 제외)
            let lookback = min(12, match.range.location)
            let precedingRange = NSRange(location: match.range.location - lookback, length: lookback)
            let preceding = ns.substring(with: precedingRange)
            if amountExcludeKeywords.contains(where: { preceding.contains($0) }) { continue }

            if seen.insert(value).inserted {
                result.append(value)
                if result.count == limit { break }
            }
        }
        return result
    }

    // MARK: - merchant candidates

    private static let merchantExcludeKeywords: [String] = [
        "승인", "일시불", "할부", "일반승인", "결제", "POS",
        "주문번호", "누적", "한도", "잔액", "서명", "캐셔",
        "과세물품가액", "부가세", "구매 영수증",
    ]

    private static let amountInLine: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\d+\s*원|\d{1,3}(?:,\d{3})+"#
    )

    private static let dateOrTimeInLine: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\d{4}[-./]\d{1,2}[-./]\d{1,2}|\b\d{1,2}/\d{1,2}\b|\d{2}:\d{2}"#
    )

    static func merchants(from ocrText: String, limit: Int = 5) -> [String] {
        let lines = splitLines(ocrText)

        var seen = Set<String>()
        var result: [String] = []
        for line in lines where !line.isEmpty {
            if line.count < 3 || line.count > 30 { continue }
            // [네이버페이 카드], [삼성페이] 같은 대괄호 결제수단 표기 제외
            if line.hasPrefix("[") { continue }
            if FoundationModelsExtractionService.isCardIssuerName(line) { continue }
            if containsMatch(amountInLine, in: line) { continue }
            if containsMatch(dateOrTimeInLine, in: line) { continue }
            if merchantExcludeKeywords.contains(where: { line.contains($0) }) { continue }
            if seen.insert(line).inserted {
                result.append(line)
                if result.count == limit { break }
            }
        }
        return result
    }

    private static func splitLines(_ ocrText: String) -> [String] {
        ocrText
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "  ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func containsMatch(_ regex: NSRegularExpression?, in line: String) -> Bool {
        guard let regex else { return false }
        let ns = line as NSString
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    // MARK: - enrich

    static func enrich(_ extraction: PaymentExtraction, ocrText: String) -> [EnrichedTransaction] {
        let merchantPool = merchants(from: ocrText, limit: 8)
        let amountPool = amounts(from: ocrText, limit: 8)
        return extraction.transactions.map { txn in
            EnrichedTransaction(
                base: txn,
                merchantCandidates: mergeMerchant(best: txn.merchant, pool: merchantPool, limit: 5),
                amountCandidates: mergeAmount(best: txn.amount, pool: amountPool, limit: 5)
            )
        }
    }

    private static func mergeMerchant(best: String, pool: [String], limit: Int) -> [String] {
        let trimmed = best.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        var seen = Set<String>()
        if !trimmed.isEmpty {
            result.append(trimmed)
            seen.insert(trimmed)
        }
        for candidate in pool where seen.insert(candidate).inserted {
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    private static func mergeAmount(best: Int, pool: [Int], limit: Int) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int>()
        if best > 0 {
            result.append(best)
            seen.insert(best)
        }
        for candidate in pool where seen.insert(candidate).inserted {
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
