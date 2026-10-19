import Foundation
import FoundationModels

@Generable struct Txn { var merchant: String; var amount: Int }
@Generable struct Out { var transactions: [Txn] }

func describe(_ label: String, _ error: any Error) {
    print("[\(label)] type:", type(of: error))
    if let e = error as? LanguageModelError {
        switch e {
        case .contextSizeExceeded(let c): print("  LanguageModelError.contextSizeExceeded size=\(c.contextSize) tokens=\(c.tokenCount)")
        default: print("  LanguageModelError other:", e)
        }
    }
    if let e = error as? LanguageModelSession.GenerationError { print("  GenerationError:", e) }
    if let e = error as? SystemLanguageModel.Error { print("  SystemLanguageModel.Error:", e) }
    print("  localizedDescription:", (error as NSError).localizedDescription)
    print("  String(describing:):", String(describing: error).prefix(300))
}

@main struct E { static func main() async {
    let long = String(repeating: "신한카드 5,800원 일시불 05/14 스타벅스 강남점 누적 1,240,500원\n", count: 400)
    print("chars:", long.count)
    // iOS 26-style init
    do {
        let s = LanguageModelSession(instructions: "카드 결제 알림에서 거래를 추출하세요.")
        _ = try await s.respond(to: long, generating: Out.self)
        print("legacy: no error")
    } catch { describe("legacy init", error) }
    // iOS 27-style init with model
    do {
        let s = LanguageModelSession(model: SystemLanguageModel.default, instructions: "카드 결제 알림에서 거래를 추출하세요.")
        _ = try await s.respond(to: long, generating: Out.self)
        print("model init: no error")
    } catch { describe("model init", error) }
    // unsupported capability (reasoning) error type
    do {
        let s = LanguageModelSession(model: SystemLanguageModel.default, instructions: "x")
        _ = try await s.respond(to: "hi", generating: Out.self, contextOptions: ContextOptions(reasoningLevel: .light))
    } catch { describe("reasoning", error) }
}}
