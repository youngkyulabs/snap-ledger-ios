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

    /// Checks whether OCR text contains payment notification signals.
    private static let paymentKeywords: [String] = [
        "승인", "일시불", "할부", "일반승인", "결제",
        "합계", "총액", "총 금액", "결제금액", "영수증",
        "현금영수증", "카드사용", "체크카드", "신용카드",
    ]

    private static let paymentSignalRegex: NSRegularExpression? = try? NSRegularExpression(
        // Currency and amount pattern matching.
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

    /// Regex for extracting candidate amount expressions.
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

            // Skip if preceding token contains forbidden keywords.
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
        pattern: #"\d{4}[-./]\d{1,2}[-./]\d{1,2}|\b\d{1,2}/\d{1,2}\b|\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp][Mm])?|\d{1,2}\s*월\s*\d{1,2}\s*일"#
    )

    private static let weekdayOnly: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\(?[월화수목금토일](요일)?\)?$"#
    )

    /// A weekday written right after a date, such as "(금)" in "10/09(금) 스타벅스".
    private static let leadingWeekday: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*(?:\(?[월화수목금토일](?:요일)?\)|[월화수목금토일]요일)\s*"#
    )

    /// Easy-pay banner layouts: "<amount>원 · <name>" and "<name>에서 <amount>원".
    private static let easyPayLayouts: [NSRegularExpression] = [
        #"[\d,]+\s*원\s*[·•ㆍ]\s*(.+)$"#,
        #"^(.+?)에서\s*[\d,]+\s*원"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Labels that follow the merchant on a notification line and end its name.
    private static let nameStopKeywords = ["누적", "잔액", "한도", "사용가능"]

    /// Names written after a date or time come first (OCR order), then plain lines (OCR order).
    static func merchants(from ocrText: String, limit: Int = 5) -> [String] {
        var seen = Set<String>()
        var named: [String] = []
        var plain: [String] = []
        for line in splitLines(ocrText) where !line.isEmpty {
            if containsMatch(dateOrTimeInLine, in: line) {
                if let name = trailingName(line), seen.insert(name).inserted { named.append(name) }
                continue
            }
            if line.count >= 3, isMerchantLike(line), seen.insert(line).inserted { plain.append(line) }
        }
        return Array((named + plain).prefix(limit))
    }

    /// The name after the last date or time on a line, such as "찌개애감동" in "10/10 12:41 찌개애감동".
    static func trailingName(_ line: String) -> String? {
        guard let regex = dateOrTimeInLine else { return nil }
        let ns = line as NSString
        guard let last = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).last else {
            return nil
        }
        return cleanedName(ns.substring(from: NSMaxRange(last.range)))
    }

    /// The merchant of an easy-pay banner line, such as "씨네Q 신도림" in "12,000원 · 씨네Q 신도림".
    static func easyPayName(_ line: String) -> String? {
        let ns = line as NSString
        for layout in easyPayLayouts {
            if let match = layout.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1,
               let name = cleanedName(ns.substring(with: match.range(at: 1))) {
                return name
            }
        }
        return nil
    }

    /// The merchant written next to a transaction's own amount: on the amount line, or after a date or time on
    /// that line or the two lines below it.
    static func anchoredMerchant(amount: Int, lines: [String]) -> String? {
        guard amount > 0 else { return nil }
        let digits = String(amount)
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset).isMultiple(of: 3) { grouped.append(",") }
            grouped.append(digit)
        }
        let amountPattern = try? NSRegularExpression(pattern: "(?<![\\d,])(?:\(grouped)(?!,?\\d)|\(digits)(?=\\s*원))")
        for (index, line) in lines.enumerated() where containsMatch(amountPattern, in: line) {
            if let name = easyPayName(line) { return name }
            for next in lines[index..<min(index + 3, lines.count)] where containsMatch(dateOrTimeInLine, in: next) {
                if let name = trailingName(next) { return name }
            }
        }
        return nil
    }

    /// Cuts a name before a running total or an amount and trims it; nil when nothing merchant-like is left.
    private static func cleanedName(_ raw: String) -> String? {
        var name = raw
        for keyword in nameStopKeywords {
            if let range = name.range(of: keyword) { name = String(name[..<range.lowerBound]) }
        }
        if let amount = amountInLine,
           let match = amount.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) {
            name = (name as NSString).substring(to: match.range.location)
        }
        if let weekday = leadingWeekday,
           let match = weekday.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) {
            name = (name as NSString).substring(from: NSMaxRange(match.range))
        }
        name = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return name.count >= 2 && isMerchantLike(name) ? name : nil
    }

    /// Whether text can be a merchant: has a letter and is not an issuer, an amount, a bookkeeping label or a bare weekday.
    private static func isMerchantLike(_ text: String) -> Bool {
        // Bracketed text is a payment method label.
        if text.count > 30 || text.hasPrefix("[") || !text.contains(where: \.isLetter) { return false }
        if FoundationModelsExtractionService.isCardIssuerName(text) { return false }
        if containsMatch(amountInLine, in: text) || containsMatch(weekdayOnly, in: text) { return false }
        return !merchantExcludeKeywords.contains { text.contains($0) }
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
        let lines = ocrText.components(separatedBy: .newlines)
        return extraction.transactions.map { txn in
            // Each payment's own line names its merchant, so it leads that payment's candidates.
            let anchored = anchoredMerchant(amount: txn.amount, lines: lines)
            let pool = anchored.map { name in [name] + merchantPool.filter { $0 != name } } ?? merchantPool
            return EnrichedTransaction(
                base: txn,
                merchantCandidates: mergeMerchant(best: txn.merchant, pool: pool, limit: 5),
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
