import Foundation

/// Classifies inbox files dropped by the share extension.
///
/// Images go through OCR; shared text is already text and skips it.
enum InboxPayload {
    /// Extension used by the share extension when it writes shared text.
    static let textExtension = "txt"

    /// Upper bound on the characters handed to extraction.
    ///
    /// The on-device model's context window also has to hold the instruction prompt, so a whole
    /// shared article would overflow it and fail late. Kept in sync with the share extension's own
    /// `maxTextLength` (a separate target cannot import this type), so the review preview shows
    /// exactly the text the model saw.
    static let extractionCharacterLimit = 2_000

    static func isText(filename: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == textExtension
    }

    static func readText(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Clamps source text to what the extraction prompt can carry.
    static func clampForExtraction(_ text: String) -> String {
        guard text.count > extractionCharacterLimit else { return text }
        return String(text.prefix(extractionCharacterLimit))
    }
}
