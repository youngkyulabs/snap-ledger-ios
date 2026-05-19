import Foundation
import Testing
import UIKit
@testable import SnapLedger

@MainActor
struct OCRServiceTests {
    @Test func emptyImageReturnsEmptyString() async throws {
        let blank = makeBlankImage(size: CGSize(width: 200, height: 100))
        let url = try writePNG(blank)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = VisionKitOCRService()
        let text = try await service.recognize(imageURL: url)
        #expect(text.isEmpty)
    }

    @Test func recognizesEnglishText() async throws {
        let img = makeTextImage("Hello World", size: CGSize(width: 800, height: 200))
        let url = try writePNG(img)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = VisionKitOCRService(languages: ["en-US"])
        let text = try await service.recognize(imageURL: url)
        #expect(text.localizedCaseInsensitiveContains("hello"))
        #expect(text.localizedCaseInsensitiveContains("world"))
    }

    @Test func recognizesKoreanText() async throws {
        let img = makeTextImage("스타벅스", size: CGSize(width: 800, height: 200))
        let url = try writePNG(img)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = VisionKitOCRService()
        let text = try await service.recognize(imageURL: url)
        #expect(text.contains("스타벅스"))
    }

    @Test func invalidURLThrowsOCRError() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID()).png")
        let service = VisionKitOCRService()
        await #expect(throws: OCRError.self) {
            _ = try await service.recognize(imageURL: bogus)
        }
    }

    // MARK: helpers

    private func makeBlankImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeTextImage(_ text: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60),
                .foregroundColor: UIColor.black,
            ]
            text.draw(at: CGPoint(x: 30, y: 50), withAttributes: attrs)
        }
    }

    private func writePNG(_ image: UIImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrtest-\(UUID()).png")
        guard let data = image.pngData() else {
            throw OCRError.invalidImage
        }
        try data.write(to: url)
        return url
    }
}
