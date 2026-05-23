import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "import")

@MainActor
enum ImageImporter {
    enum ImportError: Error, LocalizedError {
        case writeFailed(underlying: Error)
        case persistFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let err): "이미지 저장에 실패했어요: \(err.localizedDescription)"
            case .persistFailed(let err): "기록 추가에 실패했어요: \(err.localizedDescription)"
            }
        }
    }

    @discardableResult
    static func ingest(
        data: Data,
        suggestedExtension: String? = nil,
        contentType: UTType? = nil,
        in context: ModelContext
    ) throws -> String {
        let ext = resolveExtension(
            suggestedExtension: suggestedExtension,
            contentType: contentType
        )
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = AppGroup.inboxURL.appendingPathComponent(filename)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            log.error("ingest write failed: \(String(describing: error))")
            throw ImportError.writeFailed(underlying: error)
        }
        do {
            context.insert(PendingImage(filename: filename))
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            log.error("ingest persist failed: \(String(describing: error))")
            throw ImportError.persistFailed(underlying: error)
        }
        return filename
    }

    private static func resolveExtension(
        suggestedExtension: String?,
        contentType: UTType?
    ) -> String {
        if let raw = suggestedExtension {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty { return trimmed }
        }
        if let ext = contentType?.preferredFilenameExtension {
            return ext
        }
        return "img"
    }
}
