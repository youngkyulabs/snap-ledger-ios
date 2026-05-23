import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO

enum OCRError: Error {
    case invalidImage
}

protocol OCRService {
    func recognize(imageURL: URL) async throws -> String
}

struct VisionKitOCRService: OCRService {
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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                cont.resume(returning: text)
            }
            request.recognitionLanguages = languages
            request.recognitionLevel = level
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: error)
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
