import Foundation

// Usage: replay <corpus> <in.jsonl> <out.jsonl> P0|P1|P2
// Re-applies post-processing to recorded raw model output (no model calls). OCR text comes from <corpus>/ocr/.
//   P0 = the post-processing compiled in (built from the branch, that includes the branch's item filter)
//   P1 = P0 minus clock-like merchant candidates (tuning experiment)
//   P2 = P1 plus the tuning-time item filter (how the design document's routed numbers were made)

struct Raw: Decodable {
    let id: String
    let cat: String
    let cond: String
    let run: Int
    let gated: Bool
    let routed: Bool?
    let raw: [[String: String]]
    let inTok: Int
    let outTok: Int
    let ms: Int
    let error: String?
}

struct Rec: Encodable {
    let id: String
    let cat: String
    let cond: String
    let run: Int
    let gated: Bool
    let routed: Bool?
    let entries: [[String: String]]
    let inTok: Int
    let outTok: Int
    let ms: Int
    let error: String?
}

let summaryKeywords = ["합계", "총액", "총 금액", "결제금액", "과세", "면세", "부가세", "부가가치", "공급가",
                       "신용카드", "체크카드", "카드번호", "승인", "할부", "일시불", "포인트", "적립", "쿠폰",
                       "거스름", "받은금액"]

func isTimeOnly(_ s: String) -> Bool {
    s.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
}

@main
struct Replay {
    static func main() throws {
        let a = CommandLine.arguments
        let corpus = URL(fileURLWithPath: a[1])
        let variant = a[4]
        let today = ISO8601DateFormatter().date(from: "2026-10-11T08:00:00Z")!
        var texts: [String: String] = [:]
        let out = FileManager.default.createFile(atPath: a[3], contents: nil)
        precondition(out)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: a[3]))
        for line in try String(contentsOfFile: a[2], encoding: .utf8).split(separator: "\n") {
            let r = try JSONDecoder().decode(Raw.self, from: Data(line.utf8))
            if texts[r.id] == nil {
                texts[r.id] = try String(contentsOf: corpus.appendingPathComponent("ocr/\(r.id).txt"), encoding: .utf8)
            }
            let text = texts[r.id] ?? ""
            var transactions = r.raw.map { row -> PaymentTransaction in
                let items: [PaymentLineItem] = (row["items"] ?? "").isEmpty ? [] : (row["items"] ?? "")
                    .components(separatedBy: " | ").compactMap { part in
                        guard let idx = part.lastIndex(of: ":") else { return nil }
                        return PaymentLineItem(name: String(part[..<idx]), amount: Int(part[part.index(after: idx)...]) ?? 0)
                    }
                return PaymentTransaction(date: row["d"] ?? "", amount: Int(row["a"] ?? "") ?? 0,
                                          merchant: row["m"] ?? "", category: row["c"] ?? "", items: items)
            }
            if variant == "P2" {
                transactions = transactions.map { t in
                    var t = t
                    t.items = t.items.filter { item in !summaryKeywords.contains { item.name.contains($0) } }
                    return t
                }
            }
            let normalized = FoundationModelsExtractionService.normalize(
                PaymentExtraction(transactions: transactions), today: today, ocrText: text
            )
            var enriched = CandidateHeuristics.enrich(normalized, ocrText: text)
            if variant != "P0" {
                enriched = enriched.map { et in
                    var et = et
                    et.merchantCandidates = et.merchantCandidates.filter { !isTimeOnly($0) }
                    return et
                }
            }
            let entries: [[String: String]] = r.gated ? [] : enriched.flatMap { et -> [[String: String]] in
                let t = et.base
                if t.items.isEmpty {
                    let m = CandidateAutoFill.merchant(current: t.merchant, candidates: et.merchantCandidates)
                    let amt = CandidateAutoFill.amount(current: t.amount, candidates: et.amountCandidates)
                    return [["m": m, "i": "", "a": String(amt), "d": t.date]]
                }
                return t.items.map { ["m": t.merchant, "i": $0.name, "a": String($0.amount), "d": t.date] }
            }
            let rec = Rec(id: r.id, cat: r.cat, cond: r.cond, run: r.run, gated: r.gated, routed: r.routed, entries: entries,
                          inTok: r.inTok, outTok: r.outTok, ms: r.ms, error: r.error)
            var data = try JSONEncoder().encode(rec)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
        try handle.close()
    }
}
