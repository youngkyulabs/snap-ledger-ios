import Foundation
import FoundationModels
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

@Generable struct Txn { var merchant: String; var amount: Int }
@Generable struct Out { var transactions: [Txn] }

func render(_ lines: [String], to url: URL) {
    let w = 750, h = 120 + lines.count * 56
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let font = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 34, nil)
    for (i, line) in lines.enumerated() {
        let attr = NSAttributedString(string: line, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
        let ctLine = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 30, y: h - 80 - i * 56)
        CTLineDraw(ctLine, ctx)
    }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

@main struct R { static func main() async {
    let model = SystemLanguageModel.default
    // 1. reasoningLevel on the on-device model
    for level in [ContextOptions.ReasoningLevel.light, .deep] {
        let s = LanguageModelSession(model: model, instructions: "카드 결제 알림에서 거래를 추출하세요.")
        do {
            let r = try await s.respond(to: "신한카드 5,800원 일시불 05/14 스타벅스 강남점 누적 1,240,500원", generating: Out.self,
                                        contextOptions: ContextOptions(reasoningLevel: level))
            print("reasoning \(level): OK ->", r.content, "usage in/out/reasoning:", r.usage.input.totalTokenCount, r.usage.output.totalTokenCount, r.usage.output.reasoningTokenCount)
        } catch { print("reasoning \(level): ERROR ->", String(describing: error)) }
    }
    // 2. image attachment token cost on the on-device model
    let url = URL(fileURLWithPath: "notif.png")
    render(["[신한카드] 승인 김O규님", "5,800원 일시불", "05/14 13:22", "스타벅스 강남점", "누적 1,240,500원"], to: url)
    let s2 = LanguageModelSession(model: model, instructions: "카드 결제 알림에서 거래를 추출하세요.")
    do {
        let r = try await s2.respond(generating: Out.self) {
            Attachment(imageURL: url)
            "위 이미지에서 거래를 추출하세요."
        }
        print("image-only: ->", r.content, "usage in:", r.usage.input.totalTokenCount, "out:", r.usage.output.totalTokenCount)
    } catch { print("image-only: ERROR ->", String(describing: error)) }
    let s3 = LanguageModelSession(model: model, instructions: "카드 결제 알림에서 거래를 추출하세요.")
    do {
        let r = try await s3.respond(to: "신한카드 5,800원 일시불 05/14 스타벅스 강남점 누적 1,240,500원", generating: Out.self)
        print("text-only: ->", r.content, "usage in:", r.usage.input.totalTokenCount, "out:", r.usage.output.totalTokenCount)
    } catch { print("text-only: ERROR ->", String(describing: error)) }
}}
