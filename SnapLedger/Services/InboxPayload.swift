import Foundation

/// Classifies inbox files dropped by the share extension.
///
/// Images go through OCR; shared text is already text and skips it.
enum InboxPayload {
    /// Extension used by the share extension when it writes shared text.
    static let textExtension = "txt"

    static func isText(filename: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == textExtension
    }

    static func readText(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
