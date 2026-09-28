import Foundation
import Vision
import CoreGraphics
import ImageIO

enum OCRError: Error {
    case invalidImage
}

protocol OCRService: Sendable {
    func recognize(imageURL: URL) async throws -> String
}

nonisolated struct VisionKitOCRService: OCRService {
    let languages: [String]
    let level: VNRequestTextRecognitionLevel

    init(
        languages: [String] = ["ko-KR", "en-US"],
        level: VNRequestTextRecognitionLevel = .accurate
    ) {
        self.languages = languages
        self.level = level
    }

    func recognize(imageURL: URL) async throws -> String {
        guard let cgImage = Self.loadCGImage(from: imageURL) else {
            throw OCRError.invalidImage
        }
        return try await recognize(cgImage: cgImage)
    }

    func recognize(cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, any Error>) in
            // Vision can report a failure through both the completion handler and `perform`.
            let once = ResumeOnce(cont)
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        once.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    once.resume(returning: text)
                }
                request.recognitionLanguages = languages
                request.recognitionLevel = level
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage)
                do {
                    try handler.perform([request])
                } catch {
                    once.resume(throwing: error)
                }
            }
        }
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
