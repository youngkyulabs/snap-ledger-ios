import Foundation
import FoundationModels

// Usage: probe <corpus> <out.jsonl> <runs> <conds|ocr> [ids]
//   conds: comma list of A, B1, B2 (and R when built with -D ROUTED); `ocr` only writes <corpus>/ocr/<id>.txt.
// Mirrors PendingProcessor.process: OCR -> payment-signal gate -> extract -> normalize -> enrich -> entries.
//   A  = text only, the app's instructions (records the raw model output for replay)
//   B1 = photo, then the OCR text, same instructions
//   B2 = B1 plus one instruction line about the photo
//   R  = the app's own FoundationModelsExtractionService.extract(from:imageURL:) (route decided by the app)

struct Case: Decodable {
    let id: String
    let cat: String
    let file: String
}

struct Rec: Encodable {
    let id: String
    let cat: String
    let cond: String
    let run: Int
    let gated: Bool
    let routed: Bool?
    let entries: [[String: String]]
    let raw: [[String: String]]
    let inTok: Int
    let outTok: Int
    let ms: Int
    let error: String?
}

enum Cond: String {
    case A, B1, B2, R
}

let imageLine = "입력에 화면 이미지가 함께 오면, 이미지로 화면 배치를 보고 결제 알림·영수증에 해당하는 부분만 거래로 추출하세요. 금액·날짜 숫자는 OCR 텍스트를 기준으로 읽으세요."

func entries(_ enriched: [EnrichedTransaction]) -> [[String: String]] {
    enriched.flatMap { et -> [[String: String]] in
        let t = et.base
        if t.items.isEmpty {
            let m = CandidateAutoFill.merchant(current: t.merchant, candidates: et.merchantCandidates)
            let a = CandidateAutoFill.amount(current: t.amount, candidates: et.amountCandidates)
            return [["m": m, "i": "", "a": String(a), "d": t.date]]
        }
        return t.items.map { ["m": t.merchant, "i": $0.name, "a": String($0.amount), "d": t.date] }
    }
}

func rawRows(_ x: PaymentExtraction) -> [[String: String]] {
    x.transactions.map { t in
        ["m": t.merchant, "a": String(t.amount), "d": t.date, "c": t.category,
         "items": t.items.map { "\($0.name):\($0.amount)" }.joined(separator: " | ")]
    }
}

func milliseconds(_ d: Duration) -> Int {
    Int(d.components.seconds * 1000) + Int(d.components.attoseconds / 1_000_000_000_000_000)
}

/// One model call for A/B1/B2; returns the raw response so the replay tool can re-run post-processing.
func respond(_ cond: Cond, text: String, url: URL, instructions: String) async throws
    -> LanguageModelSession.Response<PaymentExtraction> {
    switch cond {
    case .B1, .B2:
        let session = LanguageModelSession(instructions: cond == .B2 ? instructions + "\n\n" + imageLine : instructions)
        return try await session.respond(generating: PaymentExtraction.self) {
            Attachment(imageURL: url)
            text
        }
    default:
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: text, generating: PaymentExtraction.self)
    }
}

func record(_ c: Case, _ cond: Cond, run: Int, text: String, url: URL, instructions: String, today: Date) async -> Rec {
    let gated = !CandidateHeuristics.hasPaymentSignal(text)
    if gated {
        return Rec(id: c.id, cat: c.cat, cond: cond.rawValue, run: run, gated: true, routed: nil,
                   entries: [], raw: [], inTok: 0, outTok: 0, ms: 0, error: nil)
    }
    let start = ContinuousClock.now
    do {
        #if ROUTED
        if cond == .R {
            let service = FoundationModelsExtractionService(customGuide: "", categories: AppSettings.defaultPresets)
            let routed = FoundationModelsExtractionService.shouldAttachImage(
                ocrText: text, hasImage: true,
                supportsVision: SystemLanguageModel.default.capabilities.contains(.vision)
            )
            let normalized = try await service.extract(from: text, imageURL: url)
            let elapsed = ContinuousClock.now - start
            return Rec(id: c.id, cat: c.cat, cond: cond.rawValue, run: run, gated: false, routed: routed,
                       entries: entries(CandidateHeuristics.enrich(normalized, ocrText: text)), raw: [],
                       inTok: 0, outTok: 0, ms: milliseconds(elapsed), error: nil)
        }
        #endif
        let response = try await respond(cond, text: text, url: url, instructions: instructions)
        let elapsed = ContinuousClock.now - start
        let normalized = FoundationModelsExtractionService.normalize(response.content, today: today, ocrText: text)
        return Rec(id: c.id, cat: c.cat, cond: cond.rawValue, run: run, gated: false, routed: cond != .A,
                   entries: entries(CandidateHeuristics.enrich(normalized, ocrText: text)),
                   raw: rawRows(response.content),
                   inTok: response.usage.input.totalTokenCount, outTok: response.usage.output.totalTokenCount,
                   ms: milliseconds(elapsed), error: nil)
    } catch {
        return Rec(id: c.id, cat: c.cat, cond: cond.rawValue, run: run, gated: false, routed: nil,
                   entries: [], raw: [], inTok: 0, outTok: 0, ms: 0, error: "\(type(of: error)): \(error)")
    }
}

@main
struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 5 else {
            print("usage: probe <corpus> <out.jsonl> <runs> <conds|ocr> [ids]")
            exit(64)
        }
        let corpus = URL(fileURLWithPath: args[1])
        let outURL = URL(fileURLWithPath: args[2])
        let runs = Int(args[3]) ?? 3
        let ocrOnly = args[4] == "ocr"
        let conds = ocrOnly ? [] : args[4].split(separator: ",").compactMap { Cond(rawValue: String($0)) }
        let only: Set<String>? = args.count > 5 ? Set(args[5].split(separator: ",").map(String.init)) : nil

        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: corpus.appendingPathComponent("truth.json")))
            .filter { only?.contains($0.id) ?? true }
        let ocr = VisionKitOCRService()
        var texts: [String: String] = [:]
        let ocrDir = corpus.appendingPathComponent("ocr")
        try FileManager.default.createDirectory(at: ocrDir, withIntermediateDirectories: true)
        for c in cases {
            let text = try await ocr.recognize(imageURL: corpus.appendingPathComponent(c.file))
            texts[c.id] = text
            try text.write(to: ocrDir.appendingPathComponent("\(c.id).txt"), atomically: true, encoding: .utf8)
        }
        if ocrOnly {
            print("ocr written: \(cases.count)")
            return
        }

        let today = Date.now
        let instructions = FoundationModelsExtractionService.instructions(
            today: today, customGuide: "", categories: AppSettings.defaultPresets
        )
        // Warm-up so the first timed call does not include model load.
        _ = try? await LanguageModelSession(instructions: "Say OK.").respond(to: "OK")

        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outURL)
        let encoder = JSONEncoder()
        for run in 1...runs {
            for c in cases {
                for cond in conds {
                    let rec = await record(c, cond, run: run, text: texts[c.id] ?? "",
                                           url: corpus.appendingPathComponent(c.file),
                                           instructions: instructions, today: today)
                    var line = try encoder.encode(rec)
                    line.append(0x0A)
                    try handle.write(contentsOf: line)
                    print("run \(run) \(c.id) \(cond.rawValue) entries=\(rec.entries.count) ms=\(rec.ms)\(rec.error.map { " ERR \($0)" } ?? "")")
                }
            }
        }
        try handle.close()
        print("done")
    }
}
